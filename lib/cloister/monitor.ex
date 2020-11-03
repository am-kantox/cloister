defmodule Cloister.Monitor do
  @moduledoc """
  The actual process that performs the monitoring of the cluster and invokes callbacks.

  This process is started and supervised by `Cloister.Manager`.
  """
  use GenServer

  use Boundary, deps: [Cloister.Modules], exports: []

  alias HashRing.Managed, as: Ring

  require Logger

  @typedoc "Statuses the node running the code might be in regard to cloister"
  @type status :: :down | :starting | :joined | :up | :stopping | :rehashing | :panic

  @typedoc "Group of nodes sharing the same hashring"
  @type group :: {atom(), [node()]}

  @typedoc "Type of the node as it has been started"
  @type node_type :: :longnames | :shortnames | :nonode

  @typedoc "The monitor internal state"
  @type t :: %{
          __struct__: Cloister.Monitor,
          otp_app: atom(),
          groups: [group()],
          listener: module(),
          started_at: DateTime.t(),
          status: status(),
          alive?: boolean(),
          clustered?: boolean(),
          sentry?: boolean(),
          ring: atom()
        }

  defstruct otp_app: :cloister,
            groups: [],
            listener: nil,
            started_at: nil,
            status: :down,
            alive?: false,
            clustered?: false,
            sentry?: false,
            ring: nil

  alias Cloister.Monitor, as: Mon

  # millis
  @refresh_rate 300

  # millis
  @rpc_timeout 5_000

  # millis
  @nodes_delay 1_000

  @doc """
  Used to start `Cloister.Monitor`.

  Internally called by `Cloister.Manager.start_link/1`. In most cases
    you don’t need to start `Monitor` process explicitly.
  """
  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {state, opts} = Keyword.pop(opts, :state, [])

    GenServer.start_link(
      __MODULE__,
      state,
      Keyword.put_new(opts, :name, __MODULE__)
    )
  end

  @impl GenServer
  @doc false
  def init(state) do
    [{top_app, _, _} | _] = Application.loaded_applications()
    otp_app = Keyword.get(state, :otp_app, top_app)

    net_kernel_magic(node_type(), otp_app)

    unless Keyword.has_key?(state, :ring),
      do: Ring.new(otp_app)

    state =
      state
      |> Keyword.put_new(:otp_app, otp_app)
      |> Keyword.put_new(:started_at, DateTime.utc_now())
      |> Keyword.put_new(:listener, Cloister.Modules.listener_module())
      |> Keyword.put_new(:status, :starting)
      |> Keyword.put_new(:ring, otp_app)

    {:ok, struct(__MODULE__, state), {:continue, :quorum}}
  end

  @impl GenServer
  @doc false
  def terminate(reason, %Mon{} = state) do
    Logger.warn(
      "[🕸️ :#{node()}] ⏹️  reason: [" <> inspect(reason) <> "], state: [" <> inspect(state) <> "]"
    )

    state = notify(:stopping, state)
    notify(:down, state)
  end

  @impl GenServer
  @doc false
  def handle_continue(:quorum, %Mon{} = state),
    do: do_handle_quorum(Node.alive?(), state)

  @spec do_handle_quorum(boolean(), state :: t()) ::
          {:noreply, new_state} | {:noreply, new_state, {:continue, :quorum}}
        when new_state: t()
  @doc false
  defp do_handle_quorum(true, %Mon{otp_app: otp_app} = state) do
    case active_sentry(otp_app) do
      [] ->
        {:noreply, state, {:continue, :quorum}}

      [_ | _] = active_sentry ->
        state = %Mon{
          state
          | alive?: true,
            sentry?: Enum.member?(active_sentry, node()),
            clustered?: true
        }

        state = update_group(:add, otp_app, node(), state)
        {:noreply, notify(:joined, state)}
    end
  end

  @doc false
  defp do_handle_quorum(false, %Mon{} = state),
    do: {:noreply, notify(:rehashing, %Mon{state | sentry?: true, clustered?: false})}

  ##############################################################################

  @spec state :: t()
  @doc "Returns an internal state of the Node"
  def state, do: GenServer.call(__MODULE__, :state)

  @spec siblings :: [node()]
  @doc "Returns the nodes in the cluster that are connected to this one in the same group"
  def siblings, do: GenServer.call(__MODULE__, :siblings)

  @spec nodes!(timeout :: non_neg_integer()) :: t()
  @doc "Rehashes the ring and returns the current state"
  def nodes!(timeout \\ @nodes_delay), do: GenServer.call(__MODULE__, :nodes!, timeout)

  @spec update_groups(args :: keyword()) :: :ok
  @doc false
  def update_groups(args), do: GenServer.cast(__MODULE__, {:update_groups, args})

  ##############################################################################

  @impl GenServer
  @doc false
  def handle_info(:update_node_list, state) do
    # Logger.debug("[🕸️ :#{node()}] 🔄 state: [" <> inspect(state) <> "]")
    {:noreply, update_state(state)}
  end

  @impl GenServer
  @doc false
  def handle_info({:nodeup, node, info}, state) do
    Logger.info(
      "[🕸️ :#{node()}] #{node} ⬆️: [" <> inspect(info) <> "], state: [" <> inspect(state) <> "]"
    )

    {:noreply, update_state(state)}
  end

  @impl GenServer
  @doc false
  def handle_info({:nodedown, node, info}, state) do
    Logger.info(
      "[🕸️ :#{node()}] #{node} ⬇️ info: [" <>
        inspect(info) <> "], state: [" <> inspect(state) <> "]"
    )

    {:noreply, update_state(state)}
  end

  ##############################################################################

  @impl GenServer
  @doc false
  def handle_call(:state, _from, state), do: {:reply, state, state}

  @impl GenServer
  @doc false
  def handle_call(:siblings, _from, %Mon{otp_app: otp_app, groups: groups} = state),
    do: {:reply, groups[otp_app], state}

  @impl GenServer
  @doc false
  def handle_call(:nodes!, _from, state) do
    state = update_state(state)
    {:reply, state, state}
  end

  @impl GenServer
  @doc false
  def handle_cast({:update_groups, _args}, %Mon{} = state) do
    Enum.each(Ring.nodes(state.ring), &Ring.remove_node(state.ring, &1))

    state = %Mon{state | groups: []}
    state = Enum.reduce([node() | Node.list()], state, &register_node/2)
    {:noreply, state}
  end

  ##############################################################################

  @spec update_state(state :: t()) :: t()
  defp update_state(%Mon{} = state) do
    state.ring
    |> Ring.nodes()
    |> do_update_state(state)
  end

  @spec do_update_state([node()] | {:error, :no_such_ring}, state :: t()) :: t()
  defp do_update_state({:error, :no_such_ring}, %Mon{} = state),
    do: state

  defp do_update_state(ring, %Mon{} = state) when is_list(ring) do
    nodes = [node() | Node.list()]

    status =
      case {ring -- nodes, nodes -- ring} do
        {[], []} ->
          :up

        {[], to_ring} ->
          Enum.each(to_ring, &register_node(&1, state))
          :rehashing

        {from_ring, []} ->
          Enum.each(from_ring, &unregister_node(&1, state))
          :rehashing

        {from_ring, to_ring} ->
          Enum.each(from_ring, &unregister_node(&1, state))
          Enum.each(to_ring, &register_node(&1, state))
          :panic
      end

    notify(status, state)
  end

  @spec notify(to :: status(), state :: t()) :: t()
  defp notify(to, %{status: to} = state), do: reschedule(state)

  defp notify(to, %{status: from} = state) do
    state = %Mon{state | status: to}
    Cloister.Modules.listener_module().on_state_change(from, state)
    reschedule(state)
  end

  @spec reschedule(state :: t()) :: t()
  defp reschedule(state) do
    Process.send_after(self(), :update_node_list, @refresh_rate)
    state
  end

  #############################################################################

  @spec node_type :: node_type()
  defp node_type do
    case node() do
      :nonode@nohost ->
        :nonode

      name ->
        name
        |> Atom.to_string()
        |> String.split("@")
        |> List.last()
        |> String.contains?(".")
        |> if(do: :longnames, else: :shortnames)
    end
  end

  @spec node_restart({:ok, binary()} | {:skip, any()}, otp_app :: atom()) ::
          {:ok, pid()} | {:error, term()}
  defp node_restart({:skip, any}, _otp_app) do
    Logger.warn("[🕸️ :#{node()}] skipping restart, expected host, got: [#{inspect(any)}].")
    {:error, any}
  end

  defp node_restart({:ok, host}, otp_app) do
    stopped = Node.stop()

    Logger.info(
      "[🕸️ :#{node()}] stopped: [#{inspect(stopped)}], starting as: [#{otp_app}@#{host}]."
    )

    Node.start(:"#{otp_app}@#{host}")
  end

  @spec net_kernel_magic(type :: node_type(), otp_app :: atom()) :: :ok
  defp net_kernel_magic(:longnames, _otp_app),
    do: :ok = :net_kernel.monitor_nodes(true, node_type: :all)

  defp net_kernel_magic(type, otp_app) do
    maybe_host =
      with service when is_atom(service) <- Application.fetch_env!(:cloister, :sentry),
           {:ok, s_ips} <- :inet_tcp.getaddrs(service),
           {:ok, l_ips} <- :inet.getifaddrs() do
        maybe_ips =
          for {_, l_ip_info} <- l_ips,
              l_ip_info_addr = l_ip_info[:addr],
              ^l_ip_info_addr <- s_ips,
              do: ip_addr_to_s(l_ip_info_addr)

        case maybe_ips do
          [] ->
            Logger.warn("[🕸️ :#{node()}] IP could not be found, retrying.")
            net_kernel_magic(type, otp_app)

          [ip | _] ->
            Logger.debug("[🕸️ :#{node()}] IP found: #{ip}")
            {:ok, ip}
        end
      else
        expected when expected == {:error, :nxdomain} or is_list(expected) ->
          magic? = Application.get_env(:cloister, :magic?, true)

          case {magic?, :inet.getifaddrs()} do
            {false, _} -> {:skip, :magic_disabled_in_config}
            {_, {:ok, ip_addrs}} when is_list(ip_addrs) -> pick_up_addr(ip_addrs)
            _ -> :inet.gethostname()
          end

        other ->
          {:skip, other}
      end

    node_restart(maybe_host, otp_app)
    net_kernel_magic(:longnames, otp_app)
  end

  @spec active_sentry(otp_app :: atom()) :: [node()]
  defp active_sentry(otp_app) do
    case Application.get_env(:cloister, :sentry, [node()]) do
      service when is_atom(service) ->
        case :inet_tcp.getaddrs(service) do
          {:ok, ip_list} ->
            for {_, _, _, _} = ip4_addr <- ip_list,
                sentry = :"#{otp_app}@#{ip_addr_to_s(ip4_addr)}",
                node() == sentry or Node.connect(sentry),
                do: sentry

          {:error, :nxdomain} ->
            Logger.warn("[🕸️ :#{node()}] Service not found: #{inspect(service)}.")
            [node()]

          {:error, reason} ->
            Logger.warn("[🕸️ #{inspect(service)}] :#{node()} ❓: #{inspect(reason)}.")
            []
        end

      [_ | _] = node_list ->
        for sentry <- node_list,
            node() == sentry or Node.connect(sentry),
            do: sentry
    end
  end

  defp loopback?, do: Application.get_env(:cloister, :loopback?, false)

  @spec ip_addr_to_s(:inet.ip4_address()) :: binary()
  defp ip_addr_to_s({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  @spec pick_up_addr([{[binary()], [any()]}]) :: {:ok, binary()} | {:skip, any()}
  defp pick_up_addr(addrs) do
    loopback = if loopback?(), do: loopback(addrs)

    case loopback || point_to_point(addrs) || broadcast(addrs) do
      addr when is_binary(addr) -> {:ok, addr}
      _other -> {:skip, {:unfit, addrs}}
    end
  end

  # second type http://erlang.org/doc/man/inet.html#type-getifaddrs_ifopts
  @spec loopback([{binary(), any()}]) :: binary() | nil
  defp loopback(addrs) do
    case Enum.filter(addrs, fn {_, addr} -> :loopback in addr[:flags] end) do
      [] -> nil
      [{_, addr}] -> ip_addr_to_s(addr[:addr])
      _many -> with {:ok, host} <- :inet.gethostname(), do: host
    end
  end

  # second type http://erlang.org/doc/man/inet.html#type-getifaddrs_ifopts
  @spec point_to_point([{binary(), any()}]) :: binary() | nil
  defp point_to_point(addrs) do
    case Enum.filter(addrs, fn {_, addr} -> :pointtopoint in addr[:flags] end) do
      [] -> nil
      [{_, addr}] -> ip_addr_to_s(addr[:addr])
      _many -> with {:ok, host} <- :inet.gethostname(), do: host
    end
  end

  # second type http://erlang.org/doc/man/inet.html#type-getifaddrs_ifopts
  @spec broadcast([{binary(), any()}]) :: binary()
  defp broadcast(addrs) do
    case Enum.filter(addrs, fn {_, addr} -> :broadcast in addr[:flags] end) do
      [{_, addr}] -> ip_addr_to_s(addr[:addr])
      _any -> with {:ok, host} <- :inet.gethostname(), do: host
    end
  end

  @spec update_group(:add | :remove, group :: atom(), who :: node(), state :: t()) :: t()
  defp update_group(:add, group, who, %Mon{groups: groups, status: :up} = state) do
    groups = Keyword.update(groups, group, [who], &Enum.uniq([who | &1]))
    %Mon{state | groups: groups}
  end

  defp update_group(:remove, group, who, %Mon{groups: groups, status: :up} = state) do
    groups = Keyword.update!(groups, group, &List.delete(&1, who))
    %Mon{state | groups: groups}
  end

  defp update_group(_, _, _, state), do: state

  @spec register_node(node :: node(), state :: t()) :: t()
  defp register_node(node, %Mon{otp_app: otp_app, ring: ring, status: :up} = state) do
    if node == node() do
      Logger.info("[🕸️ :#{node()}] ⏹️  self [#{node}] has been registered")
      Ring.add_node(ring, node)
      update_group(:add, otp_app, node, state)
    else
      case :rpc.call(node, Cloister, :ring, [], @rpc_timeout) do
        {:badrpc, reason} ->
          Logger.warn(
            "[🕸️ :#{node()}] ⏹️  attempt to call node [#{node}] failed with [#{inspect(reason)}]"
          )

          state

        ^otp_app ->
          Logger.info("[🕸️ :#{node()}] ⏹️  sibling node [#{node}] has been registered")
          Ring.add_node(ring, node)
          update_group(:add, otp_app, node, state)

        name ->
          Logger.info("[🕸️ :#{node()}] ⏹️  cousin node [#{node}] has been registered")
          update_group(:add, name, node, state)
      end
    end
  end

  # this (empty groups) happens only during Phase I
  defp register_node(node, %Mon{ring: ring, groups: []} = state) do
    Ring.add_node(ring, node)
    state
  end

  defp register_node(_node, %Mon{} = state), do: state

  @spec unregister_node(node :: node(), state :: t()) :: t()
  defp unregister_node(node, %Mon{groups: groups, ring: ring} = state) do
    Enum.reduce_while(groups, state, fn {group, nodes}, state ->
      if Enum.member?(nodes, node) do
        Ring.remove_node(ring, node)
        {:halt, update_group(:remove, group, node, state)}
      else
        {:cont, state}
      end
    end)
  end
end

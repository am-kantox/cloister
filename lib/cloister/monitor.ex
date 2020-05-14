defmodule Cloister.Monitor do
  @moduledoc """
  The actual process that performs the monitoring of the cluster and invokes callbacks.

  This process is started and supervised by `Cloister.Manager`.
  """
  use GenServer

  use Boundary, deps: [Cloister.Modules], exports: []

  require Logger

  @typedoc "Statuses the node running the code might be in regard to cloister"
  @type status :: :down | :starting | :joined | :up | :stopping | :rehashing | :panic

  @typedoc "The monitor internal state"
  @type t :: %{
          __struct__: Cloister.Monitor,
          otp_app: atom(),
          listener: module(),
          started_at: DateTime.t(),
          status: status(),
          alive?: boolean(),
          clustered?: boolean(),
          sentry?: boolean(),
          ring: atom()
        }

  defstruct otp_app: :cloister,
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

    net_kernel_magic(otp_app)

    unless Keyword.has_key?(state, :ring),
      do: HashRing.Managed.new(otp_app)

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
      "[🕸️ #{node()}] ⏹️ reason: [" <> inspect(reason) <> "], state: [" <> inspect(state) <> "]"
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
  @doc "Returns the nodes in the cluster that are connected to this one"
  def siblings, do: GenServer.call(__MODULE__, :siblings)

  @spec nodes! :: t()
  @doc "Rehashes the ring and returns the current state"
  def nodes!, do: GenServer.call(__MODULE__, :nodes!)

  ##############################################################################

  @impl GenServer
  @doc false
  def handle_info(:update_node_list, state) do
    # Logger.debug("[🕸️ #{node()}] 🔄 state: [" <> inspect(state) <> "]")
    {:noreply, update_state(state)}
  end

  @impl GenServer
  @doc false
  def handle_info({:nodeup, node, info}, state) do
    Logger.info(
      "[🕸️ #{node()}] #{node} ⬆️: [" <> inspect(info) <> "], state: [" <> inspect(state) <> "]"
    )

    {:noreply, update_state(state)}
  end

  @impl GenServer
  @doc false
  def handle_info({:nodedown, node, info}, state) do
    Logger.info(
      "[🕸️ #{node()}] #{node} ⬇️ info: [" <>
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
  def handle_call(:siblings, _from, state),
    do: {:reply, [node() | Node.list()], state}

  @impl GenServer
  @doc false
  def handle_call(:nodes!, _from, state) do
    state = update_state(state)
    {:reply, state, state}
  end

  @spec update_state(state :: t()) :: t()
  defp update_state(%Mon{} = state) do
    state.ring
    |> HashRing.Managed.nodes()
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
          Enum.each(to_ring, &HashRing.Managed.add_node(state.ring, &1))
          :rehashing

        {from_ring, []} ->
          Enum.each(from_ring, &HashRing.Managed.remove_node(state.ring, &1))
          :rehashing

        {from_ring, to_ring} ->
          Enum.each(from_ring, &HashRing.Managed.remove_node(state.ring, &1))
          Enum.each(to_ring, &HashRing.Managed.add_node(state.ring, &1))
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

  @spec net_kernel_magic(otp_app :: atom()) :: :ok
  defp net_kernel_magic(otp_app) do
    maybe_host =
      with service when is_atom(service) <- Application.get_env(:cloister, :sentry, []),
           {:ok, s_ips} <- :inet_tcp.getaddrs(service),
           {:ok, l_ips} <- :inet.getifaddrs() do
        [ip | _] =
          for {_, l_ip_info} <- l_ips,
              l_ip_info_addr = l_ip_info[:addr],
              ^l_ip_info_addr <- s_ips,
              do: ip_addr_to_s(l_ip_info_addr)

        Logger.debug("[🕸️ #{node()}] IP found: #{ip}")

        {:ok, ip}
      else
        {:error, :nxdomain} ->
          case :inet.getifaddrs() do
            {:ok, ip_addrs} when is_list(ip_addrs) ->
              {:ok, point_to_point(ip_addrs) || broadcast(ip_addrs)}

            _ ->
              :inet.gethostname()
          end

        _ ->
          :ok
      end

    with {:ok, host} <- maybe_host do
      stopped = Node.stop()

      Logger.debug(
        "[🕸️ #{node()}] stopped: [#{inspect(stopped)}], starting as: [#{otp_app}@#{host}]."
      )

      Node.start(:"#{otp_app}@#{host}")
    end

    :ok = :net_kernel.monitor_nodes(true, node_type: :all)
  end

  @spec active_sentry(otp_app :: atom()) :: [node()]
  defp active_sentry(otp_app) do
    case Application.get_env(:cloister, :sentry, [node()]) do
      service when is_atom(service) ->
        case :inet_tcp.getaddrs(service) do
          {:ok, ip_list} ->
            for {_, _, _, _} = ip4_addr <- ip_list,
                sentry = :"#{otp_app}@#{ip_addr_to_s(ip4_addr)}",
                Node.connect(sentry),
                do: sentry

          {:error, :nxdomain} ->
            Logger.warn("[🕸️ #{node()}] Service not found: #{inspect(service)}.")
            [node()]

          {:error, reason} ->
            Logger.warn("[🕸️ #{inspect(service)}] #{node()} ❓: #{inspect(reason)}.")
            []
        end

      [_ | _] = node_list ->
        for sentry <- node_list,
            Node.connect(sentry),
            do: sentry
    end
  end

  @spec ip_addr_to_s(:inet.ip4_address()) :: binary()
  defp ip_addr_to_s({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

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
end

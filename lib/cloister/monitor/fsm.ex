defmodule Cloister.Monitor.Fsm do
  @moduledoc false
  alias Cloister.Monitor, as: Mon

  @fsm """
  down --> |rehash!| rehashing
  rehashing --> |up| ready
  rehashing --> |rehash| rehashing
  rehashing --> |down| stopping
  rehashing --> |stop!| stopping
  ready --> |up| ready
  ready --> |down| ready
  ready --> |down| rehashing
  ready --> |stop!| stopping
  stopping --> |stop!| stopped
  """

  use Boundary, deps: [Cloister.Monitor], exports: []

  use Finitomata, fsm: @fsm, auto_terminate: true, timer: 1_000

  @impl Finitomata
  def on_timer(:rehashing, %Mon{} = state) do
    event = update_state(state)
  end

  @impl Finitomata
  def on_transition(:*, :__start__, _, %Mon{} = state) do
    ring = if is_nil(state.ring), do: Ring.new(state.otp_app), else: state.ring
    net_kernel_magic(node_type(), state.otp_app)

    {:ok, :down, %Mon{state | ring: ring}}
  end

  @impl Finitomata
  def on_enter(_entering, %Finitomata.State{history: [from | _], payload: state}) do
    Cloister.Modules.listener_module().on_state_change(from, state)
  end

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

    event =
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
  end

  @spec do_handle_quorum(boolean(), state :: t()) ::
          {:noreply, new_state} | {:noreply, new_state, {:continue, :quorum}}
        when new_state: t()
  @doc false
  defp do_handle_quorum(true, %Mon{otp_app: otp_app} = state) do
    case active_sentry(otp_app) do
      [] ->
        Process.sleep(@quorum_retry_interval)
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
    do: {:noreply, %Mon{state | sentry?: true, clustered?: false}}

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

            case Cloister.Application.consensus() do
              1 -> [node()]
              _ -> []
            end

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

  @spec register_node(node :: node(), state :: t()) :: t()
  defp register_node(node, %Mon{otp_app: otp_app, ring: ring} = state) do
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

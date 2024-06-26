defmodule Cloister.Monitor.Fsm do
  @moduledoc false

  alias Cloister.Monitor, as: Mon
  alias Cloister.Monitor.DistributedWatchdog, as: DW
  alias Cloister.Monitor.DistributedWatchdogSupervisor, as: DWS
  alias Finitomata.State, as: State
  alias HashRing.Managed, as: Ring

  @fsm """
  down --> |quorum!| assembling
  assembling --> |rehash| assembling
  assembling --> |sentry| assembling
  assembling --> |assembled| rehashing
  rehashing --> |nonode| nonode
  rehashing --> |rehash| rehashing
  rehashing --> |sentry| election
  rehashing --> |rehash| ready
  rehashing --> |stop!| stopping
  ready --> |nonode| nonode
  ready --> |sentry| election
  ready --> |rehash| ready
  ready --> |rehash| rehashing
  ready --> |stop!| stopping
  election --> |elected!| ready
  nonode --> |rehash!| assembling
  stopping --> |stop!| stopped
  """

  use Finitomata, fsm: @fsm, auto_terminate: true, timer: 5_000

  @typep t :: Mon.t()

  @impl Finitomata
  def on_timer(:assembling, %State{payload: %Mon{} = mon}) do
    Node.alive?()
    |> assembly_quorum(mon)
    |> case do
      :wait -> :ok
      %Mon{} = mon -> {:transition, :assembled, mon}
    end
  end

  def on_timer(current, %State{payload: %Mon{ring: ring} = mon})
      when current in ~w|rehashing ready|a do
    {nodes, ring} = nodes_vs_ring(ring)
    if MapSet.equal?(nodes, ring), do: :ok, else: {:transition, :rehash, mon}
  end

  @impl Finitomata
  def on_transition(:*, :__start__, _, %Mon{} = state) do
    net_kernel_magic(node_type(), state.otp_app, state.monitor)
    {:ok, :down, state}
  end

  def on_transition(current, :rehash, _, %Mon{ring: ring, consensus: consensus} = state)
      when current in ~w|rehashing ready|a do
    {na, nr} = nodes_vs_ring(ring)

    na |> MapSet.difference(nr) |> Enum.each(&Ring.add_node(ring, &1))
    nr |> MapSet.difference(na) |> Enum.each(&Ring.remove_node(ring, &1))

    goto =
      case length(Ring.nodes(ring)) - consensus do
        neg when neg < 0 -> :rehashing
        pos when pos >= 0 -> :ready
      end

    {:ok, goto, state}
  end

  def on_transition(current, :sentry, set?, %Mon{} = state)
      when current in ~w|rehashing ready|a do
    {:ok, :election, %Mon{state | sentry?: set?}}
  end

  def on_transition(:assembling, :sentry, _set?, %Mon{} = state) do
    {:ok, :assembling, %Mon{state | sentry?: false}}
  end

  @impl Finitomata
  def on_enter(entering, %Finitomata.State{
        history: [from | _],
        payload: %Mon{listener: listener} = state
      }) do
    downgrade =
      (match?({:ready, _}, from) or :ready == from) and :rehashing == entering

    if :ready == entering or downgrade do
      if is_nil(GenServer.whereis(DW.name(state.monitor))),
        do: Supervisor.restart_child(DWS, DW)

      DW.update_sentry(state.monitor)
    end

    cond do
      is_nil(listener) ->
        :ok

      # [AM] remove in 1.0
      function_exported?(listener, :on_state_change, 2) ->
        listener.on_state_change(normalize_state(from), state)

      true ->
        listener.on_state_change(normalize_state(from), normalize_state(entering), state)
    end
  end

  @spec normalize_state({atom(), pos_integer()} | atom()) :: atom()
  defp normalize_state({state, _num}) when is_atom(state), do: state
  defp normalize_state(state) when is_atom(state), do: state

  @spec assembly_quorum(boolean(), state :: t()) :: :wait | t()
  @doc false
  defp assembly_quorum(true, %Mon{otp_app: otp_app, consensus: consensus} = state) do
    case active_sentry(otp_app, consensus) do
      [] ->
        :wait

      [_ | _] = active_sentry ->
        %Mon{
          state
          | alive?: true,
            sentry?: Enum.member?(active_sentry, node()),
            clustered?: true
        }
    end
  end

  @doc false
  defp assembly_quorum(false, %Mon{} = state),
    do: %Mon{state | alive?: true, sentry?: true, clustered?: false}

  @spec active_sentry(otp_app :: atom(), consensus :: pos_integer()) :: [node()]
  defp active_sentry(otp_app, consensus) do
    case Application.get_env(:cloister, :sentry, [node()]) do
      service when is_atom(service) ->
        case :inet_tcp.getaddrs(service) do
          {:ok, ip_list} ->
            for {_, _, _, _} = ip4_addr <- ip_list,
                sentry = :"#{otp_app}@#{ip_addr_to_s(ip4_addr)}",
                node() == sentry or Node.connect(sentry),
                do: sentry

          {:error, :nxdomain} ->
            Logger.warning("[🕸️ :#{node()}] Service not found: #{inspect(service)}.")

            case consensus do
              1 -> [node()]
              _ -> []
            end

          {:error, reason} ->
            Logger.warning("[🕸️ #{inspect(service)}] :#{node()} ❓: #{inspect(reason)}.")
            []
        end

      [_ | _] = node_list ->
        for sentry <- node_list,
            node() == sentry or Node.connect(sentry),
            do: sentry
    end
  end

  @spec net_kernel_magic(type :: Mon.node_type(), otp_app :: atom(), monitor :: module()) :: :ok
  defp net_kernel_magic(:longnames, _otp_app, monitor),
    do: send(monitor, :monitor_nodes)

  defp net_kernel_magic(:shortnames, _otp_app, monitor),
    do: send(monitor, :monitor_nodes)

  defp net_kernel_magic(type, otp_app, monitor) do
    {type, _} =
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
            Logger.warning("[🕸️ :#{node()}] IP could not be found, retrying.")
            net_kernel_magic(type, otp_app, monitor)

          [ip | _] ->
            Logger.debug("[🕸️ :#{node()}] IP found: #{ip}")
            {:longnames, ip}
        end
      else
        expected when expected == {:error, :nxdomain} or is_list(expected) ->
          magic? = Application.get_env(:cloister, :magic?, :longnames)

          case {magic?, :inet.getifaddrs()} do
            {falsey, _} when falsey in [false, :nohost] ->
              {:skip, :magic_disabled_in_config}

            {truthy, {:ok, ip_addrs}} when truthy in [true, :longnames] and is_list(ip_addrs) ->
              pick_up_addr(ip_addrs)

            _ ->
              with {:ok, shortname} <- :inet.gethostname(), do: {:shortnames, shortname}
          end

        other ->
          {:skip, other}
      end

    node_restart(maybe_host, otp_app)
    net_kernel_magic(type, otp_app, monitor)
  end

  defp loopback?, do: Application.get_env(:cloister, :loopback?, false)

  @spec ip_addr_to_s(:inet.ip4_address()) :: binary()
  defp ip_addr_to_s({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  @spec pick_up_addr([{[binary()], [any()]}]) :: {:longnames, binary()} | {:skip, any()}
  defp pick_up_addr(addrs) do
    loopback = if loopback?(), do: loopback(addrs)

    case loopback || point_to_point(addrs) || broadcast(addrs) do
      addr when is_binary(addr) -> {:longnames, addr}
      _other -> {:skip, {:unfit, addrs}}
    end
  end

  # second type http://erlang.org/doc/man/inet.html#type-getifaddrs_ifopts
  @spec loopback([{binary(), any()}]) :: binary() | nil
  defp loopback(addrs) do
    case Enum.filter(addrs, fn {_, addr} -> :loopback in addr[:flags] end) do
      [] -> nil
      [{_, addr} | _] -> ip_addr_to_s(addr[:addr])
      _many -> with {:ok, host} <- :inet.gethostname(), do: host
    end
  end

  # second type http://erlang.org/doc/man/inet.html#type-getifaddrs_ifopts
  @spec point_to_point([{binary(), any()}]) :: binary() | nil
  defp point_to_point(addrs) do
    case Enum.filter(addrs, fn {_, addr} -> :pointtopoint in addr[:flags] end) do
      [] -> nil
      [{_, addr} | _] -> ip_addr_to_s(addr[:addr])
      _many -> with {:ok, host} <- :inet.gethostname(), do: host
    end
  end

  # second type http://erlang.org/doc/man/inet.html#type-getifaddrs_ifopts
  @spec broadcast([{binary(), any()}]) :: binary()
  defp broadcast(addrs) do
    case Enum.filter(addrs, fn {_, addr} -> :broadcast in addr[:flags] end) do
      [{_, addr} | _] -> ip_addr_to_s(addr[:addr])
      _any -> with {:ok, host} <- :inet.gethostname(), do: host
    end
  end

  @spec node_restart(
          {:shortnames, binary()} | {:longnames, binary()} | {:skip, any()},
          otp_app :: atom()
        ) ::
          {:ok, pid()} | {:error, term()}
  defp node_restart({:skip, any}, _otp_app) do
    Logger.warning("[🕸️ :#{node()}] skipping restart, expected host, got: [#{inspect(any)}].")
    {:error, any}
  end

  defp node_restart({type, host}, otp_app) when type in [:shortnames, :longnames] do
    stopped = Node.stop()

    Logger.info(
      "[🕸️ :#{node()}] stopped: [#{inspect(stopped)}], starting as: [#{otp_app}@#{host}]."
    )

    Node.start(:"#{otp_app}@#{host}", type)
  end

  @spec node_type :: Mon.node_type()
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

  @spec nodes_vs_ring(atom()) :: {MapSet.t(node()), MapSet.t(node())}
  defp nodes_vs_ring(ring),
    do: {MapSet.new([node() | Node.list()]), MapSet.new(Ring.nodes(ring))}
end

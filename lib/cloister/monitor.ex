defmodule Cloister.Monitor do
  @moduledoc """
  The actual process that performs the monitoring of the cluster and invokes callbacks.

  This process is started and supervised by `Cloister.Manager`.
  """
  use GenServer

  require Logger

  alias Cloister.Monitor, as: Mon
  alias HashRing.Managed, as: Ring

  @typedoc "Type of the node as it has been started"
  @type node_type :: :longnames | :shortnames | :nonode

  @typedoc "Monitor state"
  @type monitor :: %{
          fsm: Finitomata.fsm_name(),
          ring: atom(),
          groups: [node()]
        }

  @typedoc "The monitor internal state"
  @type t :: %{
          __struct__: Cloister.Monitor,
          otp_app: atom(),
          node: node(),
          consensus: pos_integer(),
          listener: module(),
          monitor: module(),
          started_at: DateTime.t(),
          alive?: boolean(),
          clustered?: boolean(),
          sentry?: boolean(),
          ring: atom()
        }

  defstruct otp_app: :cloister,
            node: nil,
            consensus: 1,
            listener: nil,
            monitor: nil,
            started_at: nil,
            alive?: false,
            clustered?: false,
            sentry?: false,
            ring: nil

  # millis
  @nodes_delay 1_000

  @otp_app Application.compile_env(:cloister, :otp_app, :cloister)

  @doc """
  Used to start `Cloister.Monitor`.

  Internally called by `Cloister.Manager.start_link/1`. In most cases
    you don’t need to start `Monitor` process explicitly.
  """
  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {state, opts} = Keyword.pop(opts, :state, [])
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    GenServer.start_link(
      __MODULE__,
      Keyword.put(state, :monitor, name),
      Keyword.put(opts, :name, name)
    )
  end

  @impl GenServer
  @doc false
  def init(state) do
    ring =
      case Ring.nodes(state[:ring]) do
        nodes when is_list(nodes) ->
          state[:ring]

        {:error, :no_such_ring} ->
          {:ok, _ring} = Ring.new(@otp_app)
          @otp_app
      end

    state =
      state
      |> Keyword.put(:otp_app, @otp_app)
      |> Keyword.put(:node, node())
      |> Keyword.put_new(:ring, ring)
      |> Keyword.put_new(:listener, Cloister.Modules.listener_module())
      |> Keyword.put_new(:started_at, DateTime.utc_now())
      |> Keyword.put_new(:consensus, Application.get_env(:cloister, :consensus))

    monitor_state = struct(Mon, state)

    fsm_name = fsm_name(monitor_state)
    Finitomata.start_fsm(Cloister, fsm_name, Cloister.Monitor.Fsm, monitor_state)

    {:ok, %{fsm: fsm_name, ring: ring, groups: []}}
  end

  @impl GenServer
  @doc false
  def terminate(reason, %{fsm: fsm}) do
    Logger.warning("[🕸️ :#{node()}] ⏹️  reason: [" <> inspect(reason) <> "]")
    Finitomata.transition(Cloister, fsm, {:stop!, %{reason: reason}})
  end

  @impl GenServer
  @doc false
  def handle_info({action, node, info}, state) when action in ~w|nodedown nodeup|a do
    log = %{nodedown: "⬇️", nodeup: "⬆️"}

    Logger.info(
      "[🕸️ :#{node()}] #{node} #{log[action]} info: [" <>
        inspect(info) <> "], state: [" <> inspect(state) <> "]"
    )

    Finitomata.transition(Cloister, state.fsm, :rehash)

    {:noreply, state}
  end

  @impl GenServer
  @doc false
  def handle_info(:monitor_nodes, state) do
    :net_kernel.monitor_nodes(true, node_type: :visible)
    {:noreply, state}
  end

  @doc false
  def fsm_name(%Mon{otp_app: otp_app}), do: "monitor_#{otp_app}"
  def fsm_name(otp_app), do: "monitor_#{otp_app}"

  @spec state(module(), timeout(), non_neg_integer()) :: monitor()
  @doc "Returns an internal state of the Node"
  def state(name \\ __MODULE__, timeout \\ 60_000, retries \\ 5)
  def state(_name, _timeout, retries) when retries <= 0, do: nil

  def state(name, timeout, retries) do
    GenServer.call(name, :state, timeout)
  catch
    :badrpc, {:EXIT, {:noproc, {GenServer, :call, [^name, :state, timeout]}}} ->
      Process.sleep(Enum.min([timeout, 1_000]))
      state(name, timeout, retries - 1)

    :exit, {:noproc, {GenServer, :call, [^name, :state, timeout]}} ->
      Process.sleep(Enum.min([timeout, 1_000]))
      state(name, timeout, retries - 1)
  end

  @spec siblings(module()) :: [node()] | {:error, :no_such_ring}
  @doc "Returns the nodes in the cluster that are connected to this one in the same group"
  def siblings(name \\ __MODULE__) do
    %{ring: ring} = state(name)
    Ring.nodes(ring)
  end

  @doc false
  @doc deprecated: "Use `siblings/1` instead"
  def siblings!(name \\ __MODULE__), do: siblings(name)

  @doc "Rehashes the ring and returns the current state"
  @doc deprecated: "Use `siblings/0` instead"
  def nodes!(timeout \\ @nodes_delay), do: GenServer.call(__MODULE__, :nodes!, timeout)

  ##############################################################################

  @impl GenServer
  @doc false
  def handle_call(:state, _from, state) do
    state = %{
      state
      | groups: [
          ring: Ring.nodes(state.ring),
          cluster: [node() | Node.list()]
        ]
    }

    {:reply, state, state}
  end

  @impl GenServer
  @doc false
  def handle_call(:nodes!, _from, state) do
    {:reply, state.groups, state}
  end
end

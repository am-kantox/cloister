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
          alive?: boolean(),
          clustered?: boolean(),
          sentry?: boolean(),
          ring: atom()
        }

  defstruct otp_app: :cloister,
            groups: [],
            listener: nil,
            started_at: nil,
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

  # millis
  @quorum_retry_interval 100

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
    otp_app = fn ->
      Keyword.get(state, :otp_app) ||
        case Application.loaded_applications() do
          [{top_app, _, _} | _] -> top_app
          _ -> :closter
        end
    end

    state =
      state
      |> Keyword.put_new_lazy(:otp_app, otp_app)
      |> Keyword.put_new(:listener, Cloister.Modules.listener_module())

    fsm_name = "monitor_#{state[:otp_app]}"

    Finitomata.start_fsm(Cloister.Monitor.Fsm, fsm_name)

    {:ok, %{fsm: fsm_name}}
  end

  @impl GenServer
  @doc false
  def terminate(reason, %{fsm: fsm}) do
    Logger.warn("[🕸️ :#{node()}] ⏹️  reason: [" <> inspect(reason) <> "]")
    Finitomata.transition(fsm, {:stop!, %{reason: reason}})
  end

  ##############################################################################

  @spec state :: t()
  @doc "Returns an internal state of the Node"
  def state, do: GenServer.call(__MODULE__, :state)

  @spec siblings :: [node()]
  @doc "Returns the nodes in the cluster that are connected to this one in the same group"
  def siblings, do: GenServer.call(__MODULE__, :siblings)

  @doc false
  @spec siblings! :: [node()] | {:error, :no_such_ring}
  def siblings! do
    %Mon{otp_app: otp_app, groups: groups} = nodes!()
    groups[otp_app] || Cloister.Modules.info_module().nodes()
  end

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
end

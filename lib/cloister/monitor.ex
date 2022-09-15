defmodule Cloister.Monitor do
  @moduledoc """
  The actual process that performs the monitoring of the cluster and invokes callbacks.

  This process is started and supervised by `Cloister.Manager`.
  """
  use GenServer

  use Boundary, deps: [Cloister.Modules], exports: []

  require Logger

  alias Cloister.Monitor, as: Mon
  alias HashRing.Managed, as: Ring

  @typedoc "Statuses the node running the code might be in regard to cloister"
  @type status :: :down | :starting | :joined | :up | :stopping | :rehashing | :panic

  @typedoc "Group of nodes sharing the same hashring"
  @type group :: {atom(), [node()]}

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
    otp_app = Keyword.get_lazy(state, :otp_app, fn -> Keyword.get(state, :otp_app, :cloister) end)

    ring =
      with nil <- state[:ring],
           {:ok, ring} = Ring.new(otp_app),
           do: ring,
           else: (_ -> state[:ring])

    state =
      state
      |> Keyword.put_new(:otp_app, otp_app)
      |> Keyword.put_new(:ring, ring)
      |> Keyword.put_new(:listener, Cloister.Modules.listener_module())
      |> Keyword.put_new(:consensus, Application.get_env(:cloister, :consensus))

    fsm_name = "monitor_#{state[:otp_app]}"

    Finitomata.start_fsm(Cloister.Monitor.Fsm, fsm_name, struct!(Mon, state))

    {:ok, %{fsm: fsm_name, ring: ring, groups: []}}
  end

  @impl GenServer
  @doc false
  def terminate(reason, %{fsm: fsm}) do
    Logger.warn("[🕸️ :#{node()}] ⏹️  reason: [" <> inspect(reason) <> "]")
    Finitomata.transition(fsm, {:stop!, %{reason: reason}})
  end

  @impl GenServer
  @doc false
  def handle_info({action, node, info}, state) when action in ~w|nodedown nodeup|a do
    log = %{nodedown: "⬇️", nodeup: "⬆️"}

    Logger.info(
      "[🕸️ :#{node()}] #{node} #{log[action]} info: [" <>
        inspect(info) <> "], state: [" <> inspect(state) <> "]"
    )

    Finitomata.transition(state.fsm, {:rehash, nil})

    {:noreply, state}
  end

  @impl GenServer
  @doc false
  def handle_info(:monitor_nodes, state) do
    :net_kernel.monitor_nodes(true, node_type: :all)
    {:noreply, state}
  end

  @spec state :: monitor()
  @doc "Returns an internal state of the Node"
  def state, do: __MODULE__ |> GenServer.call(:state) |> Map.put(:groups, siblings!())

  @spec siblings :: [node()]
  @doc "Returns the nodes in the cluster that are connected to this one in the same group"
  def siblings do
    case siblings!() do
      {:error, :no_such_ring} -> []
      list when is_list(list) -> list
    end
  end

  @doc false
  @spec siblings! :: [node()] | {:error, :no_such_ring}
  def siblings! do
    %Mon{ring: ring} = nodes!()
    Ring.nodes(ring)
  end

  @spec nodes!(timeout :: non_neg_integer()) :: t()
  @doc "Rehashes the ring and returns the current state"
  def nodes!(timeout \\ @nodes_delay), do: GenServer.call(__MODULE__, :nodes!, timeout)

  ##############################################################################

  @impl GenServer
  @doc false
  def handle_call(:state, _from, state), do: {:reply, state, state}

  @impl GenServer
  @doc false
  def handle_call(:nodes!, _from, state) do
    {:reply, Finitomata.state(state.fsm).payload, state}
  end
end

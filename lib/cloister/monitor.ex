defmodule Cloister.Monitor do
  @moduledoc false
  use GenServer

  use Boundary, deps: [], exports: []

  require Logger

  @type status :: :down | :starting | :up | :stopping | :rehashing | :panic

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
  @refresh_rate 1_000

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

    unless Keyword.has_key?(state, :ring),
      do: HashRing.Managed.new(otp_app)

    state =
      state
      |> Keyword.put_new(:otp_app, otp_app)
      |> Keyword.put_new(:started_at, DateTime.utc_now())
      |> Keyword.put_new(:status, :starting)
      |> Keyword.put_new(:ring, otp_app)

    :ok = :net_kernel.monitor_nodes(true, node_type: :all)
    {:ok, struct(__MODULE__, state), {:continue, :quorum}}
  end

  @impl GenServer
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
    active_sentry =
      for sentry <- Application.get_env(otp_app, :sentry, [node()]),
          Node.connect(sentry),
          do: sentry

    if active_sentry != [] do
      state = %Mon{
        state
        | alive?: true,
          sentry?: Enum.member?(active_sentry, node()),
          clustered?: true
      }

      {:noreply, notify(:up, state)}
    else
      {:noreply, state, {:continue, :quorum}}
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
  @doc "Returns whether the requested amount of nodes in the cluster are connected"
  def siblings, do: GenServer.call(__MODULE__, :siblings)

  @spec nodes! :: t()
  @doc "Rehashes the ring and returns the current state"
  def nodes!, do: GenServer.call(__MODULE__, :nodes!)

  ##############################################################################

  @impl GenServer
  def handle_info(:update_node_list, state) do
    # Logger.debug("[🕸️ #{node()}] 🔄 state: [" <> inspect(state) <> "]")
    {:noreply, update_state(state)}
  end

  @impl GenServer
  def handle_info({:nodeup, node, info}, state) do
    Logger.info(
      "[🕸️ #{node()}] #{node} ⬆️: [" <> inspect(info) <> "], state: [" <> inspect(state) <> "]"
    )

    {:noreply, update_state(state)}
  end

  @impl GenServer
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
    ring = HashRing.Managed.nodes(state.ring)
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
    apply(state.listener, :on_state_change, [from, state])
    reschedule(state)
  end

  @spec reschedule(state :: t()) :: t()
  defp reschedule(state) do
    Process.send_after(self(), :update_node_list, @refresh_rate)
    state
  end
end

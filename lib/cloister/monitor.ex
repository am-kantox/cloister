defmodule Cloister.Monitor do
  @moduledoc false
  use GenServer
  require Logger

  @type status :: :down | :starting | :up | :stopping | :panic

  @type t :: %{
          otp_app: atom(),
          status: status(),
          alive?: boolean(),
          clustered?: boolean(),
          sentry?: boolean(),
          siblings: [node()],
          ring: HashRing.t() | nil
        }

  defstruct otp_app: :cloister, status: :down, alive?: false,
            clustered?: false, sentry?: false, siblings: [], ring: nil

  alias Cloister.Monitor, as: Mon

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
      |> Keyword.put_new(:status, :starting)
      |> Keyword.put_new(:otp_app, otp_app)
      |> Keyword.put_new(:ring, otp_app)

    :ok = :net_kernel.monitor_nodes(true, node_type: :all)
    {:ok, struct(__MODULE__, state), {:continue, :quorum}}
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
    Logger.info("[🕸️] #{node()} 🏃‍♀️: [" <> inspect({otp_app, active_sentry}) <> "]")

    if active_sentry != [] do
      {:noreply,
       %Mon{
         state
         | alive?: true,
           sentry?: Enum.member?(active_sentry, node()),
           clustered?: true
       }}
    else
      {:noreply, state, {:continue, :quorum}}
    end
  end

  @doc false
  defp do_handle_quorum(false, state),
    do: {:noreply, %Mon{state | sentry?: true, clustered?: false}}

  ##############################################################################

  @spec state :: t()
  @doc "Returns an internal state of the Node"
  def state, do: GenServer.call(__MODULE__, :state)

  @spec siblings :: boolean()
  @doc "Returns whether the requested amount of nodes in the cluster are connected"
  def siblings, do: GenServer.call(__MODULE__, :siblings)

  ##############################################################################

  @impl GenServer
  def handle_info({:nodeup, node, info}, state) do
    Logger.info("[🕸️] #{node} ⬆️: [" <> inspect(info) <> "], state: [" <> inspect(state) <> "]")

    HashRing.Managed.add_node(state.ring, node)
    siblings = [node | state.siblings]
    status = check_nodes(HashRing.Managed.nodes(state.ring), state)

    {:noreply, %Mon{state | siblings: siblings, status: status}}
  end

  @impl GenServer
  def handle_info({:nodedown, node, info}, state) do
    Logger.info("[🕸️] #{node} ⬇️ info: [" <> inspect(info) <> "], state: [" <> inspect(state) <> "]")

    HashRing.Managed.remove_node(state.ring, node)
    siblings = List.delete(state.siblings, node)
    status = check_nodes(HashRing.Managed.nodes(state.ring), state)

    {:noreply, %Mon{state | siblings: siblings, status: status}}
  end

  ##############################################################################

  @impl GenServer
  @doc false
  def handle_call(:state, _from, state), do: {:reply, state, state}

  @impl GenServer
  @doc false
  def handle_call(:siblings, _from, state) do
    connected =
      :connected
      |> Elixir.Node.list()
      |> Enum.count()
      |> Kernel.+(1)

    expected = Application.get_env(state.otp_app, :consensus, 1)

    result =
      case connected - expected do
        0 -> :ok
        i when i > 0 -> {:ok, [expected: expected, connected: connected]}
        i when i < 0 -> {:error, [expected: expected, connected: connected]}
      end

    {:reply, result, state}
  end

  @spec check_nodes(ring :: list(), state :: t()) :: status()
  defp check_nodes(ring, state) do
    consensus = Application.get_env(state.otp_app, :consensus, 1)

    [ring, state.siblings]
    |> Enum.map(&Enum.sort/1)
    |> Enum.reduce(&==/2)
    |> if do
      if consensus <= Enum.count(state), do: :up, else: :starting
    else
      :panic
    end
  end
end

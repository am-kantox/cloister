defmodule Cloister.Node do
  @moduledoc """
  The state of the cloister. This process runs under supervision and makes sure
  the cluster is up-to-date with the expectations.
  """
  alias Cloister.Node, as: N

  use GenServer

  defstruct otp_app: :cloister, clustered?: false, sentry?: false, alive?: false

  @typedoc "Internal representation of the Node managed by Cloister"
  @type t :: %__MODULE__{}

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, struct(Cloister.Node, opts), name: __MODULE__)

  @impl GenServer
  def init(state), do: {:ok, state, {:continue, :quorum}}

  @impl GenServer
  def handle_continue(:quorum, %N{} = state),
    do: do_handle_quorum(Node.alive?(), state)

  @spec do_handle_quorum(boolean(), state :: t()) ::
          {:noreply, new_state} | {:noreply, new_state, {:continue, term()}}
        when new_state: term()
  defp do_handle_quorum(true, %N{otp_app: otp_app} = state) do
    active_sentry =
      for sentry <- Application.fetch_env!(otp_app, :sentry),
          Node.connect(sentry),
          do: sentry

    if active_sentry != [] do
      {:noreply,
       %N{
         state
         | alive?: true,
           sentry?: Enum.member?(active_sentry, Node.self()),
           clustered?: true
       }}
    else
      {:noreply, state, {:continue, :quorum}}
    end
  end

  defp do_handle_quorum(false, state),
    do: {:noreply, %N{state | sentry?: true, clustered?: false}}

  ##############################################################################

  @spec state :: t()
  @doc "Returns an internal state of the Node"
  def state, do: GenServer.call(__MODULE__, :state)

  @spec siblings :: boolean()
  @doc "Returns whether the requested amount of nodes in the cluster are connected"
  def siblings, do: GenServer.call(__MODULE__, :siblings)

  @spec multicast(name :: GenServer.name(), request :: term()) :: :abcast
  @doc "Casts the request to all the nodes connected to this node"
  def multicast(name, request),
    do: GenServer.abcast(name, request)

  ##############################################################################

  @impl GenServer
  def handle_call(:state, _from, state), do: {:reply, state, state}

  @impl GenServer
  def handle_call(:siblings, _from, state) do
    connected =
      :connected
      |> Elixir.Node.list()
      |> Enum.count()
      |> Kernel.+(1)

    expected = Application.fetch_env!(state.otp_app, :consensus)

    result =
      case connected - expected do
        0 -> :ok
        i when i > 0 -> {:ok, [expected: expected, connected: connected]}
        i when i < 0 -> {:error, [expected: expected, connected: connected]}
      end

    {:reply, result, state}
  end
end

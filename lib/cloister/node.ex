defmodule Cloister.Node do
  @moduledoc """
  The state of the cloister. This process runs under supervision and makes sure
  the cluster is up-to-date with the expectations.
  """
  alias Cloister.Node, as: N

  use GenServer

  defstruct otp_app: :cloister, ready: false, sentry?: false

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, struct(Cloister.Node, opts), name: __MODULE__)
  end

  @impl GenServer
  def init(state), do: {:ok, state, {:continue, :quorum}}

  @impl GenServer
  def handle_continue(:quorum, %N{} = state) do
    active_sentry =
      for sentry <- Application.fetch_env!(state.otp_app, :sentry),
          Node.connect(sentry),
          do: sentry

    if active_sentry,
      do: {:noreply, %N{state | sentry?: Enum.member?(active_sentry, Node.self()), ready: true}},
      else: {:noreply, state, {:continue, :quorum}}
  end

  def state(name \\ __MODULE__), do: GenServer.call(name, :state)

  @impl GenServer
  def handle_call(:state, _from, state), do: {:reply, state, state}
end

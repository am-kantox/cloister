defmodule Cloister.Monitor.Fsm do
  @moduledoc """
  Finite Automata for the `Cloister.Monitor` worker.
  """

  use Boundary, deps: [], exports: []

  alias Cloister.Monitor, as: Mon
  alias Cloister.Monitor.Fsm

  require Logger

  @typedoc "The internal state of the FSM behind"
  @type state :: %{
    __struct__: Fsm,
    monitor: pid(),
    sentry?: boolean(),
    cluster?: boolean(),
    listener: module()
  }

  defstruct [:monitor, :sentry?, :cluster?, :listener]

  @fsm """
  down --> |rehash| rehashing
  rehashing --> |wait| rehashing
  rehashing --> |wait| up
  rehashing --> |stop| stopping
  up --> |rehash| rehashing
  up --> |stop| stopping
  stopping --> |terminate| terminated
  """

  use Finitomata, fsm: @fsm

  @impl Finitomata
  def on_transition(_, :rehash, %Mon{} = event_payload, %Fsm{} = state_payload) do
    {:ok, :rehashing, state_payload}
  end

  @impl Finitomata
  def on_transition(_, :wait, %Mon{} = event_payload, %Fsm{} = state_payload) do
    do_wait(Node.alive?(), state_payload)
  end

  @impl Finitomata
  def on_transition(_, :stop, %Mon{} = event_payload, %Fsm{} = state_payload) do
    {:ok, :stopping, state_payload}
  end

  @impl Finitomata
  def on_transition(_, :terminated, %{reason: reason}, %Fsm{} = _state_payload) do
    Logger.warn("[🕸️ :#{node()}] ⏹️  reason: [" <> inspect(reason) <> "]")
    {:ok, :terminated, state_payload}
  end

  @spec do_wait(boolean(), state()) :: {:ok, :up | :}
  defp do_wait(false, %Fsm{} = state) do
    {:ok, :up, %Fsm{state | sentry: true, cluster?: false}}
  end

  defp do_wait(false, %Fsm{} = state) do
    {:ok, :up, %Fsm{state | sentry: true, cluster?: false}}
  end
end

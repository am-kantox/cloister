defmodule Cloister.Listener do
  @moduledoc """
  The behavior to be implemented by `Cloister.Monitor` listeners.
  """

  @doc """
  Passed to the `Cloister.Monitor.start_link/1` and is being called
  on each subsequent monitored node state change.

  Listeners are obliged to handle `:up`, `:rehashing` and `:stopping` events.

  Please note, that since `v0.18.0`, the interface has changed to include
    the state `to`. Consumers need to update their code because in `v1.0.0`
    the obsoleted callback `on_state_change/2` will be removed.
  """
  @callback on_state_change(
              from :: Cloister.Monitor.Fsm.state(),
              to :: Cloister.Monitor.Fsm.state(),
              state :: Cloister.Monitor.t()
            ) :: :ok
end

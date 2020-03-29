defmodule Cloister.Listener do
  @moduledoc """
  The behavior to be implemented by `Cloister.Monitor` listeners.
  """

  @doc """
  Passed to the `Cloister.Monitor.start_link/1` and is being called
  on each subsequent monitored node state change.

  Listeners are obliged to handle `:up`, `:rehashing` and `:stopping` events.
  """
  @callback on_state_change(
              from :: Cloister.Monitor.status(),
              state :: Cloister.Monitor.t()
            ) :: :ok
end

defmodule Cloister.Monitor.Fsm do
  @moduledoc """
  Finite Automata for the `Cloister.Monitor` worker.
  """

  @fsm """
  down --> |start| starting
  starting --> |init| rehashing
  rehashing --> |wait| up
  rehashing --> |stop| stopping
  up --> |rehash| rehashing
  up --> |stop| stopping
  stopping --> |terminate| terminated
  """

  use Finitomata, fsm: @fsm
end

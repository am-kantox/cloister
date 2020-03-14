defmodule Cloister.Message do
  @moduledoc "The message to be used in multicall requests"

  @typedoc "Stage of message round-robin passing, a map of stage numbers to hashes"
  @type stages :: %{required(non_neg_integer()) => binary()}

  @typedoc "The type of multicall request"
  @type t :: %{
          __struct__: Cloister.Message,
          from: nil | pid(),
          stages: stages(),
          message: term()
        }

  defstruct message: nil, from: nil, stages: %{}
end

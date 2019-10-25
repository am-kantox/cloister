defmodule Cloister.Attendee do
  @typedoc "The internal representation of the node in the cluster"
  @type t :: %{
          node: Node.t(),
          state: :up | :down | :unknown,
          __struct__: atom()
        }
  defstruct node: Node.self(), state: :up
end

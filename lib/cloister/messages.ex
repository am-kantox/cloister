defmodule Cloister.Message do
  defmodule Prepare do
    @typedoc "The internal representation of the prepare message in the cluster"
    @type t :: %{
            self: Cloister.Attendee.t(),
            n: non_neg_integer(),
            __struct__: atom()
          }

    @enforce_keys [:self, :n]
    defstruct self: %Cloister.Attendee{}, n: 0

    def inc(%Cloister.Message.Prepare{n: n} = msg),
      do: %Cloister.Message.Prepare{msg | n: n + 1}
  end
end

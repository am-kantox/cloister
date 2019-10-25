defmodule Cloister.Quorum do
  @typedoc "The internal representation of the quorum in the cluster"
  @type t :: %{
          config: keyword(),
          self: Cloister.Attendee.t(),
          siblings: %{required(atom()) => Cloister.Attendee.t()},
          __struct__: atom()
        }

  defstruct config: [], self: %Cloister.Attendee{}

  def quorum?(sentries) when is_atom(sentries), do: quorum?([sentries])

  def quorum?(sentries) when is_list(sentries) do
    active_setry = for(sentry <- sentries, Node.connect(sentry), do: sentry)
    {not Enum.empty?(active_setry), Node.list(:connected)}
  end
end

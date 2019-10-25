defmodule Cloister.Behaviours do
  defmodule Prepare do
    @callback prepare(message: %Cloister.Message.Prepare{}, quorum: Cloister.Quorum.t()) :: :ok
  end
end

defmodule Cloister.Behaviours do
  defmodule Proposer do
    @callback prepare(message: Cloister.Message.Prepare.t()) :: :ok
  end
end

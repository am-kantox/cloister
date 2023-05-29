defmodule Mix.Tasks.Cloister.Init do
  @shortdoc "Init the `:closter` MIX_ENV for Cloister"
  @moduledoc """
  Mix task to create the dedicated environment for Cloister.
  """

  use Mix.Task

  @impl Mix.Task
  @doc false
  def run(args) do
    {opts, [], []} =
      OptionParser.parse(args,
        strict: [application: :string, ip: :string, consensus: :integer, log: :string]
      )

    Cloister.Mix.Commons.gen_config(opts)
  end
end

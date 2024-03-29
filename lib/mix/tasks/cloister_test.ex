defmodule Mix.Tasks.Cloister.Test do
  @shortdoc "Run tests in Cloister"
  @moduledoc """
  Mix task to run test in previously started Cloister env.
  """

  use Mix.Task

  import Cloister.Mix.Commons

  @impl Mix.Task
  @doc false
  def run(args) do
    {[], pass_thru, []} = OptionParser.parse(args, strict: [])

    if config?() do
      epmd_port = spawn_epmd()
      ports = spawn_nodes()

      Mix.shell().info([:green, "* spawned ", :reset, inspect(epmd: epmd_port, nodes: ports)])

      spawn_this()
      Mix.Tasks.Test.run(pass_thru)

      cleanup([epmd_port | ports])
    end
  end
end

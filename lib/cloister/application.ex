defmodule Cloister.Application do
  @moduledoc false

  use Application

  #! TODO MOVE MONKS UNDER CLOISTER SUPERVISION
  def start(_type, _args) do
    :ok = Application.ensure_started(:libring, :permanent)
    HashRing.Managed.new(:cloister, monitor_nodes: true)

    monks = generate_agents()
    HashRing.Managed.new(:monks, nodes: monks)

    additional_modules =
      Enum.filter(
        Application.get_env(:cloister, :additional_modules, []),
        &ensure_compiled?/1
      )

    children =
      [
        Cloister,
        Cloister.Node
      ] ++ monks ++ additional_modules

    opts = [strategy: :one_for_one, name: Cloister.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp generate_agents() do
    count = Application.get_env(:cloister, :agents, 3)
    Enum.map(1..count, &Cloister.Agent.agent!("R#{&1}"))
  end

  defp ensure_compiled?(module) do
    case Code.ensure_compiled(module) do
      {:module, _module} -> true
      {:error, _reason} -> false
    end
  end
end

defmodule Cloister.Application do
  @moduledoc false

  use Application

  #! TODO MOVE MONKS UNDER CLOISTER SUPERVISION
  def start(_type, _args) do
    :ok = Application.ensure_started(:libring, :permanent)

    additional_modules =
      Enum.filter(
        Application.get_env(:cloister, :additional_modules, []),
        &ensure_compiled?/1
      )

    children =
      [
        Cloister,
        {Cloister.Monitor, [state: [otp_app: :cloister]]},
        Cloister.Node
      ] ++ additional_modules

    opts = [strategy: :one_for_one, name: Cloister.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp ensure_compiled?(module) do
    case Code.ensure_compiled(module) do
      {:module, _module} -> true
      {:error, _reason} -> false
    end
  end
end

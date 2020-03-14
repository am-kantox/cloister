defmodule Cloister.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    additional_modules =
      Enum.filter(
        Application.get_env(:cloister, :additional_modules, []),
        &ensure_compiled?/1
      )

    children =
      [
        Cloister,
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

defmodule Cloister.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    additional_modules =
      Enum.filter(
        Application.get_env(:cloister, :additional_modules, []),
        &Code.ensure_compiled?/1
      )

    children =
      [
        Cloister,
        Cloister.Node
      ] ++ additional_modules

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cloister.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

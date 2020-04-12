defmodule Cloister.Application do
  @moduledoc false

  use Application

  require Logger

  @consensus 3
  @consensus_timeout 3_000

  @impl Application
  def start(_type, _args) do
    children = [
      Cloister.Manager
    ]

    opts = [strategy: :one_for_one, name: Cloister.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def prep_stop(_state),
    do: Cloister.Monitor.terminate({:shutdown, :application}, Cloister.Monitor.state())

  @impl Application
  def start_phase(:warming_up, _start_type, phase_args) do
    phase_args
    |> Keyword.get(:consensus, Application.get_env(:cloister, :consensus, @consensus))
    |> wait_consensus()
  end

  @spec wait_consensus(consensus :: non_neg_integer(), retries :: non_neg_integer()) :: :ok
  defp wait_consensus(consensus, retries \\ 1) do
    nodes = Cloister.Modules.info_module().nodes()

    nodes
    |> Enum.count()
    |> case do
      n when n < consensus ->
        message = "[🕸️ #{node()}] ⏳ retries: [#{retries}], nodes: [" <> inspect(nodes) <> "]"

        case div(retries, 10) do
          0 -> Logger.warn(message)
          _ -> Logger.debug(message)
        end

        Process.sleep(@consensus_timeout)
        wait_consensus(consensus, retries + 1)

      _ ->
        Logger.info("[🕸️ #{node()}] ⌛ retries: [#{retries}], nodes: [" <> inspect(nodes) <> "]")
    end
  end
end

defmodule Cloister.Application do
  @moduledoc false

  use Application

  require Logger

  @consensus 3
  @consensus_timeout 1_000

  @impl Application
  def start(_type, _args) do
    Logger.debug(
      "[🕸️ :#{node()}] starting cloister with config:\n" <>
        inspect(Application.get_all_env(:cloister))
    )

    manager = Application.get_env(:cloister, :manager, [])

    children = [
      {Cloister.Manager, [manager]}
    ]

    opts = [strategy: :one_for_one, name: Cloister.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def prep_stop(_state),
    do: Cloister.Monitor.terminate({:shutdown, :application}, Cloister.Monitor.state())

  @impl Application
  def start_phase(:warming_up, _start_type, phase_args) do
    cloister_consensus =
      Keyword.get(phase_args, :consensus, Application.get_env(:cloister, :consensus, @consensus))

    Process.put(:cloister_consensus, cloister_consensus)

    Logger.info(
      "[🕸️ :#{node()}] Cloister → Phase I. Warming up, waiting for consensus [#{cloister_consensus}]."
    )

    wait_consensus(cloister_consensus, 0)
    :ok
  end

  @impl Application
  def start_phase(:rehash_on_up, _start_type, phase_args) do
    Logger.info("[🕸️ :#{node()}] Cloister → Phase II. Updating groups.")
    Cloister.Monitor.update_groups(phase_args)
    :ok
  end

  @spec consensus :: non_neg_integer()
  def consensus, do: Process.get(:cloister_consensus, @consensus)

  @spec wait_consensus(consensus :: non_neg_integer(), retries :: non_neg_integer()) :: :ok
  defp wait_consensus(consensus, retries) do
    Process.sleep(@consensus_timeout)
    # Cloister.siblings!()
    do_wait_consensus(Cloister.Modules.info_module().nodes(), consensus, retries)
  end

  @spec do_wait_consensus(
          [node()] | {:error, :no_such_ring},
          consensus :: non_neg_integer(),
          retries :: non_neg_integer()
        ) :: :ok
  defp do_wait_consensus({:error, :no_such_ring}, consensus, retries),
    do: wait_consensus(consensus, retries)

  defp do_wait_consensus(nodes, consensus, retries) when is_list(nodes) do
    nodes
    |> Enum.count()
    |> case do
      n when n < consensus ->
        message = "[🕸️ :#{node()}] ⏳ retries: [#{retries}], nodes: [" <> inspect(nodes) <> "]"

        case div(retries, 10) do
          0 -> Logger.info(message)
          n when n < 100 and rem(retries, 10) == 0 -> Logger.warn(message)
          _ when rem(retries, 100) == 0 -> Logger.error(message)
        end

        wait_consensus(consensus, retries + 1)

      _ ->
        Logger.info("[🕸️ :#{node()}] ⌚ retries: [#{retries}], nodes: [" <> inspect(nodes) <> "]")
    end
  end
end

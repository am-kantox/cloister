defmodule Cloister.Monitor.DistributedWatchdog do
  @moduledoc false

  use GenServer

  @otp_app Application.compile_env(:cloister, :otp_app, :cloister)

  def start_link(monitor \\ Cloister.Monitor) do
    with {:error, {:already_started, _pid}} <-
           GenServer.start_link(__MODULE__, %{otp_app: @otp_app, sentry: nil, monitor: monitor},
             name: name(monitor)
           ) do
      :ignore
    end
  end

  def update_sentry(monitor \\ Cloister.Monitor) do
    Process.sleep(1)

    monitor
    |> name()
    |> GenServer.whereis()
    |> case do
      nil -> update_sentry(monitor)
      target -> GenServer.cast(target, :update_sentry)
    end
  end

  def name(monitor), do: {:global, Module.concat(monitor, DistributedWatchdog)}

  @impl GenServer
  def init(%{} = state), do: {:ok, state}

  @impl GenServer
  def handle_cast(:update_sentry, %{} = state) do
    {sentry, changed?} =
      case Cloister.sentry(state.monitor) do
        {:ok, node} ->
          {node, false}

        {:error, []} ->
          Finitomata.transition(
            Cloister,
            Cloister.Monitor.fsm_name(state.otp_app),
            {:sentry, true}
          )

          {node(), true}

        {:error, monitors} ->
          nodes = Enum.map(monitors, & &1.node)
          sentry = Enum.random(nodes)

          Cloister.multiapply(nodes -- [sentry], Finitomata, :transition, [
            Cloister,
            Cloister.Monitor.fsm_name(state.otp_app),
            {:sentry, false}
          ])

          {sentry, true}
      end

    if changed? do
      case Application.get_env(:cloister, :sentry_handler, nil) do
        nil -> :ok
        pid when is_pid(pid) -> Process.send(pid, {:sentry_changed, sentry}, [])
        name when is_atom(name) -> Process.send(name, {:sentry_changed, sentry}, [])
        {name, node} -> Process.send({name, node}, {:sentry_changed, sentry}, [])
        _ -> :ok
      end
    end

    {:noreply, %{state | sentry: sentry}}
  end
end

defmodule Cloister.Monitor.DistributedWatchdog do
  @moduledoc false

  use GenServer

  def start_link(monitor \\ Cloister.Monitor) do
    with {:error, {:already_started, pid}} <-
           GenServer.start_link(__MODULE__, %{otp_app: :cloister, sentry: nil, monitor: monitor},
             name: name(monitor)
           ) do
      {:ok, pid}
    end
  end

  def update_sentry(monitor \\ Cloister.Monitor) do
    Process.sleep(1_000)

    monitor
    |> name()
    |> GenServer.cast(:update_sentry)
  end

  def name(monitor), do: {:global, Module.concat(monitor, DistributedWatchdog)}

  @impl GenServer
  def init(%{} = state), do: {:ok, state}

  @impl GenServer
  def handle_cast(:update_sentry, %{} = state) do
    sentry =
      case Cloister.sentry(state.monitor) do
        [node] ->
          node

        _ ->
          nodes = [node() | Node.list()]
          sentry = Enum.random(nodes)

          Enum.each(nodes, fn remote ->
            :rpc.call(remote, Finitomata, :transition, [
              Cloister,
              Cloister.Monitor.fsm_name(state.otp_app),
              {:sentry, remote == sentry}
            ])
          end)

          sentry
      end

    {:noreply, %{state | sentry: sentry}}
  end
end

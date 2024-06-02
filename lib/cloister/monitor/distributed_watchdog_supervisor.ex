defmodule Cloister.Monitor.DistributedWatchdogSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(monitor) do
    Supervisor.start_link(__MODULE__, monitor, name: __MODULE__)
  end

  @impl true
  def init(monitor) do
    children = [{Cloister.Monitor.DistributedWatchdog, monitor}]
    Supervisor.init(children, strategy: :one_for_one)
  end
end

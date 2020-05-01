defmodule Cloister.Void do
  @moduledoc false

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, name: Cloister.Void)

  @impl GenServer
  def init(:ok), do: {:ok, :ok}

  @impl GenServer
  def handle_cast({:ping, pid}, :ok) do
    # IO.inspect({node(), {:ping, pid}}, label: "Received cast")
    GenServer.cast(pid, {:pong, self()})
    {:noreply, :ok}
  end

  @impl GenServer
  def handle_cast({:ping_one, pid}, :ok) do
    if Cloister.mine?({:ping_one, pid}) do
      # IO.inspect({node(), {:ping_one, pid}}, label: "Received cast")
      GenServer.cast(pid, {:pong, self()})
    end

    {:noreply, :ok}
  end

  @impl GenServer
  def handle_call({:ping, pid}, {pid, tag} = _from, :ok) do
    # IO.inspect({node(), {:ping, pid}, tag}, label: "Received call")
    GenServer.cast(pid, {:pong, self()})
    {:reply, :ok, :ok}
  end

  @impl GenServer
  def handle_call({:ping_one, pid}, {pid, tag} = _from, :ok) do
    if Cloister.mine?({:ping_one, pid}) do
      # IO.inspect({node(), {:ping_one, pid}, tag}, label: "Received call")
      GenServer.cast(pid, {:pong, self()})
    end

    {:reply, :ok, :ok}
  end
end

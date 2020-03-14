defmodule Cloister.Router do
  @moduledoc false

  defmodule State do
    @moduledoc false
    @type pending :: %{required(binary()) => Cloister.Message.t()}
    @type t :: %{
            __struct__: Cloister.Agent.State,
            pending: pending(),
            options: keyword()
          }
    defstruct pending: [], options: []
  end

  use GenServer

  alias Cloister.Message, as: Msg

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(opts), do: {:ok, %State{options: opts}}

  @impl GenServer
  def handle_call(:state, _from, state), do: {:reply, state, state}

  @impl GenServer
  def handle_call({verb, message}, {from, tag}, state) do
    {message, state} =
      message
      |> normalize()
      |> pass_thru({from, tag}, state)

    GenServer.abcast(__MODULE__, message)
    {:reply, message, state}
  end

  @spec normalize(message :: term()) :: Cloister.Message.t()
  def normalize(%Msg{} = message), do: message
  def normalize(message), do: %Msg{message: message}

  @spec pass_thru(msg :: Cloister.Message.t(), {pid(), term()}, state :: State.t()) :: term()
  defp pass_thru(%Msg{from: nil} = msg, {from, tag}, state) do
    msg = %Msg{msg | from: from, stages: %{0 => {node(), tag}}}
  end

  defp pass_thru(%Msg{from: nil} = msg, {from, tag}, state) do
    msg = %Msg{msg | from: from, stages: %{0 => tag}}
  end
end

defmodule Cloister.Actors.Proposer do
  @moduledoc false
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [name: opts[:name]] do
      @behaviour Cloister.Behaviours.Proposer
      alias Cloister.Actor.State

      @impl Cloister.Behaviours.Proposer
      def prepare(%Cloister.Message.Prepare{} = message),
        do: GenServer.call(unquote(name), {:prepare, message})

      def quorum do
        state = state()

        :connected
        |> Node.list()
        |> Enum.each(&Process.send({@name, &1}, {:prepare, state}, []))
      end

      def perform_prepare(%State{payload: %{proposer: message} = payload} = state) do
        state = %State{
          state
          | payload: %{payload | proposer: Cloister.Message.Prepare.inc(message)}
        }

        IO.inspect(state, label: "Prepare")
        {state, state}
      end

      def handle_prepare(
            %State{payload: %{acceptor: acceptor}} = remote_state,
            %State{payload: %{quorum: quorum} = payload} = state
          ) do
      end
    end
  end
end

defmodule Cloister.Helper do
  @moduledoc false
  def delegate_all(to) when is_atom(to) do
    funs = to.__info__(:functions)

    Enum.map(funs, fn
      {f, arity} ->
        args = for i <- 0..arity, i > 0, do: Macro.var(:"arg_#{i}", nil)

        quote do
          defdelegate unquote(f)(unquote_splicing(args)), to: unquote(to)
          defoverridable [{unquote(f), unquote(arity)}]
        end
    end)
  end

  defmacro ast(:proposer, name) do
    quote do
      @behaviour Cloister.Behaviours.Proposer
      @host_module unquote(name)

      @impl Cloister.Behaviours.Proposer
      def prepare(%Cloister.Message.Prepare{} = message),
        do: GenServer.cast(@host_module, {prepare, message})

      def handle_cast({:prepare, %Cloister.Message.Prepare{} = message}, state),
        do: {:noreply, state}
    end
  end

  defmacro ast(_, _), do: []
end

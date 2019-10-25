defmodule Cloister.Helper do
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
end

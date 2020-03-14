defmodule Cloister.Agent do
  @moduledoc false

  defmacro __using__(opts) do
    quote do
      use Elixir.Agent

      @name Keyword.get(unquote(opts), :name, __MODULE__)

      def start_link([]),
        do: Elixir.Agent.start_link(fn -> %{} end, name: @name)

      @spec all() :: map()
      def all(),
        do: Elixir.Agent.get(@name, Cloister.Agent, :all, [])

      @spec get(Map.key()) :: Map.value()
      def get(key),
        do: Elixir.Agent.get(@name, Cloister.Agent, :get, [key])

      @spec put(Map.key(), Map.value()) :: map()
      def put(key, value),
        do: Elixir.Agent.update(@name, Cloister.Agent, :put, [key, value])

      @spec update(Map.key(), Map.value(), (Map.value() -> Map.value())) :: map()
      def update(key, initial, fun),
        do: Elixir.Agent.update(@name, Cloister.Agent, :update, [key, initial, fun])

      @spec delete(Map.key()) :: map()
      def delete(key),
        do: Elixir.Agent.update(@name, Cloister.Agent, :delete, [key])
    end
  end

  defdelegate get(map, key), to: Map
  defdelegate put(map, key, value), to: Map
  defdelegate update(map, key, initial, fun), to: Map
  defdelegate delete(map, key), to: Map

  def all(map), do: map

  def agent!(name) when is_binary(name),
    do: agent!(Module.concat(__MODULE__, String.capitalize(name)))

  def agent!(name) when is_atom(name) do
    case Code.ensure_compiled(name) do
      {:module, module} ->
        module

      {:error, _reason} ->
        {:module, module, _, _} =
          Module.create(name, quote(do: use(Cloister.Agent)), Macro.Env.location(__ENV__))

        module
    end
  end
end

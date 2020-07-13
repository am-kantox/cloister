defmodule Cloister.Modules do
  @moduledoc false

  require Logger

  defmodule Stubs do
    @moduledoc false
    use Boundary, deps: [], exports: []

    @doc false
    @spec create_info_module(ring :: term(), name :: module()) :: module()
    def create_info_module(ring, name \\ Cloister.Monitor.Info) do
      case Code.ensure_compiled(name) do
        {:module, ^name} ->
          name

        _ ->
          ast =
            quote do
              @moduledoc false

              @spec whois(group :: atom(), term :: term(), retry? :: boolean()) ::
                      {:ok, node()} | {:error, {:not_our_ring, atom()}}
              def whois(group \\ nil, term, retry? \\ true)

              def whois(nil, term, retry?), do: whois(unquote(ring), term, retry?)

              def whois(unquote(ring), term, retry?) do
                case {retry?, HashRing.Managed.key_to_node(unquote(ring), term)} do
                  {false, {:error, {:invalid_ring, :no_nodes}} = error} ->
                    error

                  {true, {:error, {:invalid_ring, :no_nodes}}} ->
                    Cloister.Monitor.nodes!()
                    whois(unquote(ring), term, false)

                  {_, node} ->
                    {:ok, node}
                end
              end

              def whois(ring, _, _), do: {:error, {:not_out_ring, ring}}

              @spec nodes :: [term()] | {:error, :no_such_ring}
              def nodes,
                do: HashRing.Managed.nodes(unquote(ring))

              @spec ring :: atom()
              def ring, do: unquote(ring)
            end

          Module.create(name, ast, Macro.Env.location(__ENV__))
          Application.put_env(:cloister, :monitor, name, persistent: true)
          name
      end
    end

    @doc false
    @spec create_listener_module(ring :: term(), name :: module()) :: module()
    def create_listener_module(ring, name \\ Cloister.Listener.Default) do
      case Code.ensure_compiled(name) do
        {:module, ^name} ->
          name

        _ ->
          ast =
            quote do
              @moduledoc false

              @behaviour Cloister.Listener
              require Logger

              @impl Cloister.Listener
              def on_state_change(from, state) do
                Logger.debug(
                  "[🕸️ #{inspect(unquote(ring))} :#{node()}] 🔄 from: :#{from}, state: " <>
                    inspect(state)
                )
              end
            end

          Module.create(name, ast, Macro.Env.location(__ENV__))
          Application.put_env(:cloister, :listener, name, persistent: true)
          name
      end
    end
  end

  use Boundary, deps: [Cloister.Modules.Stubs], exports: []

  @compile {:inline, info_module: 0, listener_module: 0}

  @cloister_env Application.get_all_env(:cloister)

  @ring Keyword.get(@cloister_env, :ring, Application.get_env(:cloister, :otp_app, :cloister))

  @info_module Keyword.get_lazy(@cloister_env, :monitor, fn -> Stubs.create_info_module(@ring) end)
  @spec info_module :: module()
  def info_module, do: @info_module

  @listener_module Keyword.get_lazy(@cloister_env, :listener, fn ->
                     Stubs.create_listener_module(@ring)
                   end)
  @spec listener_module :: module()
  def listener_module, do: @listener_module
end

defmodule Cloister.Modules do
  @moduledoc false

  require Logger

  use Boundary, exports: [Stubs]

  defmodule Stubs do
    @moduledoc false

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

              require Logger

              @spec whois(group :: atom(), term :: term(), retry? :: boolean()) ::
                      {:ok, node()} | {:error, {:not_our_ring, atom()}}
              def whois(group \\ nil, term, retry? \\ true)

              def whois(nil, term, retry?), do: whois(unquote(ring), term, retry?)

              def whois(unquote(ring), term, retry?) do
                case {retry?, HashRing.Managed.key_to_node(unquote(ring), term)} do
                  {false, {:error, {:invalid_ring, :no_nodes}} = error} ->
                    error

                  {true, {:error, {:invalid_ring, :no_nodes}}} ->
                    try do
                      Cloister.Monitor.nodes!()
                    catch
                      :exit, _reason ->
                        Logger.warn("Ring #{unquote(ring)} is not yet assembled, retrying.")
                    end

                    whois(unquote(ring), term, false)

                  {_, node} ->
                    {:ok, node}
                end
              end

              def whois(ring, _, _), do: {:error, {:not_our_ring, ring}}

              @spec nodes :: [node()] | {:error, :no_such_ring}
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
                  "[🕸️ " <>
                    inspect(unquote(ring)) <>
                    ":#{node()}] 🔄 from: " <>
                    inspect(from) <>
                    ", state: " <>
                    inspect(state)
                )
              end
            end

          Module.create(name, ast, Macro.Env.location(__ENV__))
          name
      end
    end
  end

  @compile {:inline, info_module: 0, listener_module: 0}

  @cloister_env Application.get_all_env(:cloister)

  @ring Keyword.get(@cloister_env, :ring, Application.compile_env(:cloister, :otp_app, :cloister))

  @info_module Keyword.get_lazy(@cloister_env, :monitor, fn -> Stubs.create_info_module(@ring) end)
  @spec info_module :: module()
  def info_module, do: @info_module

  @listener_module Keyword.get_lazy(@cloister_env, :listener, fn ->
                     Stubs.create_listener_module(@ring)
                   end)
  @spec listener_module :: module()
  def listener_module, do: @listener_module
end

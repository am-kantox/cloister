defmodule Cloister.Modules do
  @moduledoc false

  require Logger

  defmodule Stubs do
    use Boundary, deps: [], exports: []

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

              @spec whois(term :: term()) :: node()
              def whois(term) do
                case HashRing.Managed.key_to_node(unquote(ring), term) do
                  {:error, {:invalid_ring, :no_nodes}} ->
                    Cloister.Monitor.nodes!()
                    whois(term)

                  node ->
                    node
                end
              end

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

              def on_state_change(from, state) do
                Logger.debug(
                  "[🕸️ #{inspect(unquote(ring))} #{node()}] 🔄 from: #{from}, state: " <>
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

  use Boundary, deps: [Stubs], exports: []

  @compile {:inline, info_module: 0, listener_module: 0}

  Logger.debug(
    "[🕸️ #{node()}] generating stubs as:\n" <>
      inspect(Application.get_all_env(:cloister))
  )

  @ring Application.get_env(:cloister, :ring, Application.get_env(:cloister, :otp_app, :cloister))

  @info_module Application.get_env(:cloister, :monitor, Stubs.create_info_module(@ring))
  @spec info_module :: module()
  def info_module, do: @info_module

  @listener_module Application.get_env(:cloister, :listener, Stubs.create_listener_module(@ring))
  @spec listener_module :: module()
  def listener_module, do: @listener_module
end

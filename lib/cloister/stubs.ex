defmodule Cloister.Modules do
  @moduledoc false

  require Logger

  defmodule Stubs do
    @moduledoc false

    defmodule Info do
      @moduledoc false

      @ring Application.compile_env(:cloister, :otp_app, :cloister)

      require Logger

      @spec whois(group :: atom(), term :: term(), retry? :: boolean()) ::
              {:ok, node()} | {:error, {:not_our_ring, atom()}}
      def whois(group \\ nil, term, retry? \\ true)

      def whois(nil, term, retry?), do: whois(@ring, term, retry?)

      def whois(@ring, term, retry?) do
        case {retry?, HashRing.Managed.key_to_node(@ring, term)} do
          {false, {:error, {:invalid_ring, :no_nodes}} = error} ->
            error

          {true, {:error, {:invalid_ring, :no_nodes}}} ->
            Logger.warning("Ring #{@ring} is not yet assembled, retrying.")
            Process.sleep(1_000)
            whois(@ring, term, true)

          {_, node} ->
            {:ok, node}
        end
      end

      def whois(ring, _, _), do: {:error, {:not_our_ring, ring}}

      @spec nodes :: [node()] | {:error, :no_such_ring}
      def nodes, do: HashRing.Managed.nodes(@ring)

      @spec ring :: atom()
      def ring, do: @ring
    end

    defmodule Listener do
      @moduledoc false

      require Logger

      @behaviour Cloister.Listener

      @ring Application.compile_env(:cloister, :otp_app, :cloister)

      @impl Cloister.Listener
      def on_state_change(from, to, state) do
        Logger.info(
          "[🕸️ " <>
            inspect(@ring) <>
            ":#{node()}] ♻  from: ‹" <>
            inspect(from) <>
            "› to: ‹" <>
            inspect(to) <>
            "›, state: " <>
            inspect(state)
        )
      end
    end
  end

  @compile {:inline, info_module: 0, listener_module: 0}

  @info_module Application.compile_env(:cloister, :monitor, Cloister.Modules.Stubs.Info)
  @spec info_module :: module()
  def info_module, do: @info_module

  @listener_module Application.compile_env(:cloister, :listener, Cloister.Modules.Stubs.Listener)
  @spec listener_module :: module()
  def listener_module, do: @listener_module
end

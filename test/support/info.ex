defmodule Cloister.Monitor.Info do
  @moduledoc false

  @spec whois(group :: atom(), term :: term(), retry? :: boolean()) ::
          {:ok, node()} | {:error, {:not_our_ring, atom()}}
  def whois(group \\ nil, term, retry? \\ true)

  def whois(nil, term, retry?), do: whois(:cloister, term, retry?)

  def whois(:cloister, term, retry?) do
    case {retry?, HashRing.Managed.key_to_node(:cloister, term)} do
      {false, {:error, {:invalid_ring, :no_nodes}} = error} ->
        error

      {true, {:error, {:invalid_ring, :no_nodes}}} ->
        Cloister.Monitor.nodes!()
        whois(:cloister, term, false)

      {_, node} ->
        {:ok, node}
    end
  end

  def whois(ring, _, _), do: {:error, {:not_out_ring, ring}}

  @spec nodes :: [term()] | {:error, :no_such_ring}
  def nodes,
    do: HashRing.Managed.nodes(:cloister)

  @spec ring :: atom()
  def ring, do: :cloister
end

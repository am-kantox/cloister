defmodule Cloister.Monitor.Info do
  def whois(term) do
    case HashRing.Managed.key_to_node(:cloister, term) do
      {:error, {:invalid_ring, :no_nodes}} ->
        Cloister.Monitor.nodes!()
        whois(term)

      node ->
        node
    end
  end
end

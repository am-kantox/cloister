defmodule Cloister do
  @moduledoc """
  `Cloister` is a consensus helper for clusters.
  """

  use DynamicSupervisor

  @spec start_link(opts :: keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl DynamicSupervisor
  def init(opts),
    do: DynamicSupervisor.init(Keyword.merge([strategy: :one_for_one], opts))

  @spec whois(term :: any()) :: node() | {:error, :no_such_ring}
  @doc "Returns who would be chosen by a hash ring for the term"
  def whois(term), do: HashRing.Managed.key_to_node(:cloister, term)

  defdelegate state, to: Cloister.Node
  defdelegate siblings, to: Cloister.Node
  defdelegate multicast(name, request), to: Cloister.Node
end

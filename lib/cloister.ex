defmodule Cloister do
  @moduledoc """
  `Cloister` is a consensus helper for clusters.
  """

  use Boundary, deps: [Cloister.{Modules, Monitor, Node}], exports: []

  use DynamicSupervisor

  @spec start_link(opts :: keyword()) :: Supervisor.on_start()
  @doc false
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl DynamicSupervisor
  @doc false
  def init(opts),
    do: DynamicSupervisor.init(Keyword.merge([strategy: :one_for_one], opts))

  @spec whois(term :: any()) :: node() | {:error, :no_such_ring}
  @doc "Returns who would be chosen by a hash ring for the term"
  def whois(term), do: Cloister.Modules.info_module().whois(term)

  @spec mine?(term :: any()) :: boolean() | {:error, :no_such_ring}
  @doc "Returns `true` if the hashring points to this node for the term given, `false` otherwise"
  def mine?(term), do: whois(term) == node()

  defdelegate state, to: Cloister.Monitor
  defdelegate siblings, to: Cloister.Monitor
  defdelegate multicast(name, request), to: Cloister.Node
  defdelegate multicall(name, request), to: Cloister.Node
  defdelegate multicall(nodes, name, request), to: Cloister.Node
end

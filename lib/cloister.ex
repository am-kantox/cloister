defmodule Cloister do
  @moduledoc ~s"""
  `Cloister` is a consensus helper for clusters.

  It is designed to be a configurable drop-in for transparent cluster support.

  ### Supported options

  #{NimbleOptions.docs(Cloister.Options.schema())}
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

  @spec whois(group :: atom(), term :: any()) ::
          node() | {:error, {:invalid_ring, :no_nodes}} | {:error, {:not_our_ring, atom()}}
  @doc "Returns who would be chosen by a hash ring for the term in the group given"
  def whois(group \\ nil, term),
    do: with({:ok, node} <- Cloister.Modules.info_module().whois(group, term), do: node)

  @spec mine?(term :: any()) :: boolean() | {:error, :no_such_ring}
  @doc "Returns `true` if the hashring points to this node for the term given, `false` otherwise"
  def mine?(term), do: whois(term) == node()

  @spec otp_app :: atom()
  @doc "Returns an `otp_app` from current node cloister monitor state"
  def otp_app, do: state().otp_app

  defdelegate state, to: Cloister.Monitor
  defdelegate siblings, to: Cloister.Monitor
  defdelegate multicast(name, request), to: Cloister.Node
  defdelegate multicall(name, request), to: Cloister.Node
  defdelegate multicall(nodes, name, request), to: Cloister.Node
end

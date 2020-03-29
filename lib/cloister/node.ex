defmodule Cloister.Node do
  @moduledoc false

  use GenServer

  @doc false
  def start_link(opts \\ []) do
    {state, opts} = Keyword.pop(opts, :state, [])

    GenServer.start_link(
      __MODULE__,
      state,
      Keyword.put_new(opts, :name, __MODULE__)
    )
  end

  @impl GenServer
  @doc false
  def init(state), do: {:ok, state}

  @spec multicast(name :: GenServer.name(), request :: term()) :: :abcast
  @doc "Casts the request to all the nodes connected to this node"
  def multicast(name, request),
    do: GenServer.abcast(name, request)

  @spec multicall(nodes :: [node()], name :: GenServer.name(), request :: term()) ::
          {replies :: [{node(), term()}], bad_nodes :: [node()]}
  @doc """
  Casts the request to all the nodes passed as a parameter.
  """
  def multicall(nodes \\ [node() | Node.list()], name, request),
    do: GenServer.multi_call(nodes, name, request)
end

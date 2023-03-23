defmodule Cloister.Node do
  @moduledoc """
  The abstraction level allowing milticalls and multicasts across the whole cluster.
  """

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

  @spec multicast(nodes :: [node()], name :: GenServer.name(), request :: term()) :: :abcast
  @doc """
  Casts the request to all the nodes connected to this node
  """
  def multicast(nodes \\ [node() | Node.list()], name, request),
    do: :rpc.eval_everywhere(nodes, GenServer, :cast, [name, request])

  @spec multicall(nodes :: [node()], name :: GenServer.name(), request :: term()) :: [term()]
  @doc """
  Casts the request to all the nodes passed as a parameter.
  """
  def multicall(nodes \\ [node() | Node.list()], name, request) do
    with {replies, _} <- :rpc.multicall(nodes, GenServer, :call, [name, request]), do: replies
  end
end

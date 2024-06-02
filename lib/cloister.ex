defmodule Cloister do
  @moduledoc ~s"""
  `Cloister` is a consensus helper for clusters.

  It is designed to be a configurable drop-in for transparent cluster support.

  ### Supported options

  #{NimbleOptions.docs(Cloister.Options.schema())}
  """

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

  @spec multiapply(nil | [node()], module(), module(), atom(), list()) :: any()
  @doc """
  Applies the function given as `m, f, a` on all the nodes given as a first parameter.

  If no `nodes` are given, it defaults to `Cloister.siblings/0`.
  """
  def multiapply(nodes \\ nil, monitor \\ Cloister.Monitor, m, f, a) do
    nodes = if is_nil(nodes), do: siblings(monitor), else: nodes
    this = node()

    case nodes do
      [^this] -> {[apply(m, f, a)], []}
      _ -> :rpc.multicall(nodes, m, f, a)
    end
  end

  @spec ring :: atom()
  @doc "Returns the `ring` from current node cloister monitor state"
  def ring, do: Cloister.Modules.info_module().ring()

  defdelegate siblings, to: Cloister.Monitor
  defdelegate siblings(monitor), to: Cloister.Monitor
  defdelegate siblings!, to: Cloister.Monitor
  defdelegate siblings!(monitor), to: Cloister.Monitor

  defdelegate multicast(name, request), to: Cloister.Node
  defdelegate multicast(nodes, name, request), to: Cloister.Node
  defdelegate multicall(name, request), to: Cloister.Node
  defdelegate multicall(nodes, name, request), to: Cloister.Node

  @doc """
  The state of this cloister.

  This function returns the value only after `Cloister.Monitor` has been started

  ```elixir
  %Cloister.Monitor{
    otp_app: :rates_blender,
    consensus: 3,
    listener: MyApp.Cloister.Listener,
    monitor: Cloister.Monitor,
    started_at: ~U[2024-05-31 05:37:40.238027Z],
    alive?: true,
    clustered?: true,
    sentry?: false,
    ring: :my_app
  }
  ```
  """
  @spec state(monitor :: module()) :: nil | Cloister.Monitor.t()
  def state(monitor \\ Cloister.Monitor) do
    with %{fsm: fsm_name} <- Cloister.Monitor.state(monitor),
         %Cloister.Monitor{} = state <- Finitomata.state(Cloister, fsm_name, :payload),
         do: state
  end

  @doc """
  Retrieves states of all the nodes in the cloister.
  """
  @spec states(monitor :: module()) :: {[Cloister.Monitor.t()], [node()]}
  def states(monitor \\ Cloister.Monitor) do
    Cloister.multiapply(Cloister, :state, [monitor])
  end

  @doc false
  @spec fsm_state(monitor :: module()) :: nil | Finitomata.State.t()
  def fsm_state(monitor \\ Cloister.Monitor) do
    with %{fsm: fsm_name} <- Cloister.Monitor.state(monitor),
         do: Finitomata.state(Cloister, fsm_name, :full)
  end

  @doc """
  Returns `{:ok, node()}` if the cloister has the only one sentry, or `{:error, [node()]`
    with the list of nodes fancied themselves a sentry. 
  """

  @spec sentry(monitor :: module()) :: {:ok, node()} | {:error, [node()]}
  def sentry(monitor \\ Cloister.Monitor) do
    monitor
    |> states()
    |> elem(0)
    |> Enum.split_with(&match?(%Cloister.Monitor{sentry?: true}, &1))
    |> case do
      {[sentry], _failed} -> {:ok, sentry}
      {unexpected, _failed} -> {:error, unexpected}
    end
  end
end

defmodule Cloister.Actor do
  @moduledoc ~s"""

  > - **Client** The _Client_ issues a request to the distributed system, and waits
  for a response. For instance, a write request on a file in a distributed file server.
  > - **Acceptor** (**Voters**) The _Acceptors_ act as the fault-tolerant "memory"
  of the protocol. _Acceptors_ are collected into groups called _Quorums_.
  Any message sent to an _Acceptor_ must be sent to a _Quorum_ of _Acceptors_.
  Any message received from an _Acceptor_ is ignored unless a copy is received
  from each _Acceptor_ in a _Quorum_.
  > - **Proposer** A _Proposer_ advocates a client request, attempting to convince
  the _Acceptors_ to agree on it, and acting as a coordinator to move the protocol
  forward when conflicts occur.
  > - **Learner** _Learners_ act as the replication factor for the protocol.
  Once a _Client_ request has been agreed upon by the _Acceptors_, the _Learner_
  may take action (i.e.: execute the request and send a response to the client).
  To improve availability of processing, additional _Learners_ can be added.
  > - **Leader** [Paxos](https://en.wikipedia.org/wiki/Paxos_(computer_science)#Basic_Paxos)
  requires a distinguished _Proposer_ (called the leader) to make progress.
  Many processes may believe they are leaders, but the protocol only guarantees
  progress if one of them is eventually chosen. If two processes believe they are
  leaders, they may stall the protocol by continuously proposing conflicting updates.
  However, the safety properties are still preserved in that case.
  """

  @roles [:client, :acceptor, :proposer, :learner, :leader]

  defmodule State do
    # @enforce_keys [:messages]
    defstruct messages: [], otp_app: :cloister, roles: [], ready: false, payload: %{}
  end

  defmacro __using__(opts) do
    roles =
      case opts[:roles] do
        nil -> @roles
        role when role in @roles -> [role]
        [_ | _] = roles -> roles
        _ -> raise "roles: must be a list of one or more " <> inspect(@roles)
      end

    delegates =
      Enum.flat_map(roles, fn role ->
        mod = Module.concat(__MODULE__, role |> to_string() |> Macro.camelize())
        Cloister.Helper.delegate_all(mod)
      end)

    [
      quote do
        use GenServer
        alias Cloister.Actor.State

        @name Keyword.get(unquote(opts), :name, __MODULE__)

        def start_link(payload) do
          GenServer.start_link(
            __MODULE__,
            %State{
              otp_app: Keyword.get(unquote(opts), :otp_app, :cloister),
              roles: unquote(roles),
              payload: payload
            },
            name: @name
          )
        end

        def state, do: GenServer.call(@name, :state)

        @impl GenServer
        def init(state), do: {:ok, state, {:continue, :quorum}}

        @impl GenServer
        def handle_continue(:quorum, %{} = state) do
          sentries = Application.fetch_env!(state.otp_app, :sentry)

          case Cloister.Quorum.quorum?(sentries) do
            {true, _} -> {:noreply, %State{state | ready: true}}
            _ -> {:noreply, state, {:continue, :quorum}}
          end
        end

        @impl GenServer
        def handle_call(:state, _from, state), do: {:reply, state, state}
      end
      | delegates
    ]
  end

  defmodule Client do
    def foo, do: 42
  end

  defmodule Proposer do
    def prepare() do
    end

    # def on_handle_prepare()
  end
end

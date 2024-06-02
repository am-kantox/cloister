defmodule CloisterTest do
  use ExUnit.Case
  use Enfiladex.Suite

  doctest Cloister

  require Logger

  @delay if Mix.env() == :ci, do: 1_000, else: 1_000

  setup_all do
    Application.put_env(:cloister, :consensus, 3)
  end

  test "sentry" do
    assert %Cloister.Monitor{
             otp_app: :cloister,
             consensus: 1,
             listener: Cloister.Modules.Stubs.Listener,
             monitor: Cloister.Monitor,
             alive?: true,
             clustered?: true,
             sentry?: true,
             ring: :cloister
           } = Cloister.state()

    assert Cloister.sentry()
  end

  test "multicasts" do
    Enfiladex.multi_peer({Cloister, :multicast, [Cloister.Void, {:ping, self()}]},
      transfer_config: :cloister,
      start_applications: :cloister,
      count: 3
    )

    Enum.each(1..3, fn _ -> assert_receive({:"$gen_cast", {:pong, _}}, @delay) end)
    assert {:message_queue_len, 0} = :erlang.process_info(self(), :message_queue_len)
  end

  test "multicalls" do
    Enfiladex.multi_peer({Cloister, :multicall, [Cloister.Void, {:ping, self()}]},
      transfer_config: :cloister,
      start_applications: :cloister,
      count: 3
    )

    Enum.each(1..3, fn _ -> assert_receive({:"$gen_cast", {:pong, _}}, @delay) end)
    assert {:message_queue_len, 0} = :erlang.process_info(self(), :message_queue_len)
  end

  test "multicasts to one" do
    Enfiladex.peer({Cloister, :multicast, [Cloister.Void, {:ping, self()}]},
      transfer_config: :cloister,
      start_applications: :cloister
    )

    assert_receive({:"$gen_cast", {:pong, _}}, @delay)
    assert {:message_queue_len, 0} = :erlang.process_info(self(), :message_queue_len)
  end

  test "multicalls to one" do
    Enfiladex.peer({Cloister, :multicall, [Cloister.Void, {:ping, self()}]},
      transfer_config: :cloister,
      start_applications: :cloister
    )

    assert_receive({:"$gen_cast", {:pong, _}}, @delay)
    assert {:message_queue_len, 0} = :erlang.process_info(self(), :message_queue_len)
  end

  test "groups" do
    {peers, nodes} =
      Enfiladex.start_peers(5,
        transfer_config: :cloister,
        start_applications: :cloister
      )

    assert [ok: _, ok: _, ok: _, ok: _, ok: _] = peers

    assert 6 = length(Cloister.Monitor.state().groups[:ring])

    for {_pid, node} <- nodes do
      assert node in Cloister.Monitor.state().groups[:ring]
    end

    assert 6 = length(Cloister.Monitor.state().groups[:cluster])

    for {_pid, node} <- nodes do
      assert node in Cloister.Monitor.state().groups[:cluster]
    end

    Enfiladex.stop_peers(peers)
  end
end

defmodule CloisterTest do
  use ExUnit.Case
  doctest Cloister

  @delay if Mix.env() == :ci, do: 5_000, else: 5_000

  test "multicasts" do
    Cloister.multicast(Cloister.Void, {:ping, self()})

    Enum.each(1..5, fn _ -> assert_receive({:"$gen_cast", {:pong, _}}, @delay) end)
    assert {:message_queue_len, 0} = :erlang.process_info(self(), :message_queue_len)
  end

  test "multicalls" do
    Cloister.multicall(Cloister.Void, {:ping, self()})

    Enum.each(1..5, fn _ -> assert_receive({:"$gen_cast", {:pong, _}}, @delay) end)
    assert {:message_queue_len, 0} = :erlang.process_info(self(), :message_queue_len)
  end

  test "multicasts to one" do
    Cloister.multicast(Cloister.Void, {:ping_one, self()})

    assert_receive({:"$gen_cast", {:pong, _}}, @delay)
    assert {:message_queue_len, 0} = :erlang.process_info(self(), :message_queue_len)
  end

  test "multicalls to one" do
    Cloister.multicall(Cloister.Void, {:ping_one, self()})

    assert_receive({:"$gen_cast", {:pong, _}}, @delay)
    assert {:message_queue_len, 0} = :erlang.process_info(self(), :message_queue_len)
  end
end

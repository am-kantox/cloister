defmodule CloisterTest do
  use ExUnit.Case
  doctest Cloister

  test "multicasts" do
    Cloister.multicast(Cloister.Void, {:ping, self()})

    Enum.each(1..5, fn _ -> assert_receive({:"$gen_cast", {:pong, _}}, 1_000) end)
    assert {:message_queue_len, 0} = :erlang.process_info(self(), :message_queue_len)
  end

  test "multicasts to one" do
    Cloister.multicast(Cloister.Void, {:ping_one, self()})

    assert_receive({:"$gen_cast", {:pong, _}}, 1_000)
    assert {:message_queue_len, 0} = :erlang.process_info(self(), :message_queue_len)
  end
end

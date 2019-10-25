defmodule CloisterTest do
  use ExUnit.Case
  doctest Cloister

  test "greets the world" do
    assert Cloister.hello() == :world
  end
end

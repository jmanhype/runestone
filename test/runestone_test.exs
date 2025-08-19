defmodule RunestoneTest do
  use ExUnit.Case
  doctest Runestone

  test "greets the world" do
    assert Runestone.hello() == :world
  end
end

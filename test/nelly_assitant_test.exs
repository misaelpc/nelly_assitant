defmodule NellyAssitantTest do
  use ExUnit.Case
  doctest NellyAssitant

  test "greets the world" do
    assert NellyAssitant.hello() == :world
  end
end

defmodule App.Model.GroupParentTest do
  use ExUnit.Case, async: true

  alias App.Model.GroupParent

  # Swiftwater starts from GSAR, and Swiftwater 2 from Swiftwater.
  @parents %{20 => 10, 30 => 20}

  test "ancestors climb to the top, nearest first" do
    assert GroupParent.ancestors(30, @parents) == [20, 10]
    assert GroupParent.ancestors(10, @parents) == []
  end

  test "a loop already in the data stops" do
    assert GroupParent.ancestors(10, %{10 => 20, 20 => 10}) == [20]
  end

  test "cannot start from itself or from a group that starts from it" do
    refute GroupParent.can_start_from?(10, 10, @parents)
    refute GroupParent.can_start_from?(10, 30, @parents)
    assert GroupParent.can_start_from?(30, 10, @parents)
  end
end

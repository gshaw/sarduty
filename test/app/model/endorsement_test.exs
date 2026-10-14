defmodule App.Model.EndorsementTest do
  use ExUnit.Case, async: true

  alias App.Model.Endorsement

  # 7h includes 40h, which includes 70h. Each lists only its own courses.
  @own %{7 => [1, 2], 40 => [3], 70 => [4, 2]}
  @includes %{7 => [40], 40 => [70]}

  test "earned by its own qualifications, then everything its includes reach" do
    assert Endorsement.earned_by_ids(7, @own, @includes) == [1, 2, 3, 4]
    assert Endorsement.earned_by_ids(40, @own, @includes) == [3, 4, 2]
    assert Endorsement.earned_by_ids(70, @own, @includes) == [4, 2]
  end

  test "a loop already in the data ends instead of running forever" do
    assert Endorsement.earned_by_ids(7, @own, %{7 => [40], 40 => [7]}) == [1, 2, 3]
  end

  test "cannot include itself or one that already reaches it" do
    refute Endorsement.can_include?(7, 7, @includes)
    refute Endorsement.can_include?(70, 7, @includes)
    refute Endorsement.can_include?(70, 40, @includes)
    assert Endorsement.can_include?(7, 70, @includes)
    assert Endorsement.can_include?(70, 99, @includes)
  end
end

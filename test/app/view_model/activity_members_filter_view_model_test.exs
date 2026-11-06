defmodule App.ViewModel.ActivityMembersFilterViewModelTest do
  use ExUnit.Case, async: true

  alias App.ViewModel.ActivityMembersFilterViewModel, as: Filter

  @groups [{"Team leaders", 7}]

  test "a group, a tile, and a search, trimmed" do
    filter =
      Filter.validate(%{"group" => "7", "status" => "no-reply", "q" => "  kow "}, @groups, false)

    assert filter == %Filter{group: 7, status: "no-reply", q: "kow"}
    assert Filter.query_params(filter) == [group: 7, status: "no-reply", q: "kow"]
    assert Filter.d4h_status(filter) == "requested"
    assert Filter.narrowed?(filter)
  end

  test "each tile's word before the start and from it" do
    for {slug, d4h} <- [
          {"signed-up", "attending"},
          {"cant-make-it", "absent"},
          {"no-reply", "requested"}
        ] do
      assert %Filter{status: ^slug} =
               filter = Filter.validate(%{"status" => slug}, @groups, false)

      assert Filter.d4h_status(filter) == d4h
      assert Filter.slug(d4h, false) == slug
    end

    for {slug, d4h} <- [
          {"attended", "attending"},
          {"absent", "absent"},
          {"no-reply", "requested"}
        ] do
      assert %Filter{status: ^slug} = filter = Filter.validate(%{"status" => slug}, @groups, true)
      assert Filter.d4h_status(filter) == d4h
      assert Filter.slug(d4h, true) == slug
    end
  end

  test "a part that doesn't fit filters nothing, and leaves the rest" do
    assert Filter.validate(%{"status" => "attended"}, @groups, false) == %Filter{}
    assert Filter.validate(%{"status" => "signed-up"}, @groups, true) == %Filter{}

    assert Filter.validate(%{"status" => "maybe", "q" => "riley"}, @groups, true) == %Filter{
             q: "riley"
           }

    assert Filter.validate(%{"group" => "abc", "status" => "absent"}, @groups, true) ==
             %Filter{status: "absent"}

    assert Filter.validate(%{"group" => "8"}, @groups, true) == %Filter{}
    assert Filter.validate(%{"q" => "   "}, @groups, true) == %Filter{}
  end

  test "the tile alone doesn't narrow, and an empty filter writes no params" do
    refute Filter.narrowed?(%Filter{status: "absent"})
    assert Filter.query_params(%Filter{}) == []
  end
end

defmodule App.ViewModel.ActivityMembersFilterViewModelTest do
  use ExUnit.Case, async: true

  alias App.ViewModel.ActivityMembersFilterViewModel

  @groups [{"Team leaders", 7}]

  test "a group, a tile, and a search, trimmed" do
    filter =
      ActivityMembersFilterViewModel.validate(
        %{"group" => "7", "status" => "no-reply", "q" => "  kow "},
        @groups,
        false
      )

    assert filter == %ActivityMembersFilterViewModel{group: 7, status: "no-reply", q: "kow"}

    assert ActivityMembersFilterViewModel.query_params(filter) == [
             group: 7,
             status: "no-reply",
             q: "kow"
           ]

    assert ActivityMembersFilterViewModel.d4h_status(filter) == "requested"
    assert ActivityMembersFilterViewModel.narrowed?(filter)
  end

  test "each tile's word before the start and from it" do
    for {slug, d4h} <- [
          {"signed-up", "attending"},
          {"cant-make-it", "absent"},
          {"no-reply", "requested"}
        ] do
      assert %ActivityMembersFilterViewModel{status: ^slug} =
               filter =
               ActivityMembersFilterViewModel.validate(%{"status" => slug}, @groups, false)

      assert ActivityMembersFilterViewModel.d4h_status(filter) == d4h
      assert ActivityMembersFilterViewModel.slug(d4h, false) == slug
    end

    for {slug, d4h} <- [
          {"attended", "attending"},
          {"absent", "absent"},
          {"no-reply", "requested"}
        ] do
      assert %ActivityMembersFilterViewModel{status: ^slug} =
               filter =
               ActivityMembersFilterViewModel.validate(%{"status" => slug}, @groups, true)

      assert ActivityMembersFilterViewModel.d4h_status(filter) == d4h
      assert ActivityMembersFilterViewModel.slug(d4h, true) == slug
    end
  end

  test "a part that doesn't fit filters nothing, and leaves the rest" do
    assert ActivityMembersFilterViewModel.validate(%{"status" => "attended"}, @groups, false) ==
             %ActivityMembersFilterViewModel{}

    assert ActivityMembersFilterViewModel.validate(%{"status" => "signed-up"}, @groups, true) ==
             %ActivityMembersFilterViewModel{}

    assert ActivityMembersFilterViewModel.validate(
             %{"status" => "maybe", "q" => "riley"},
             @groups,
             true
           ) == %ActivityMembersFilterViewModel{
             q: "riley"
           }

    assert ActivityMembersFilterViewModel.validate(
             %{"group" => "abc", "status" => "absent"},
             @groups,
             true
           ) ==
             %ActivityMembersFilterViewModel{status: "absent"}

    assert ActivityMembersFilterViewModel.validate(%{"group" => "8"}, @groups, true) ==
             %ActivityMembersFilterViewModel{}

    assert ActivityMembersFilterViewModel.validate(%{"q" => "   "}, @groups, true) ==
             %ActivityMembersFilterViewModel{}
  end

  test "the tile alone doesn't narrow, and an empty filter writes no params" do
    refute ActivityMembersFilterViewModel.narrowed?(%ActivityMembersFilterViewModel{
             status: "absent"
           })

    assert ActivityMembersFilterViewModel.query_params(%ActivityMembersFilterViewModel{}) == []
  end
end

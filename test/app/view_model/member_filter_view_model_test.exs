defmodule App.ViewModel.MemberFilterViewModelTest do
  use ExUnit.Case, async: true

  alias App.ViewModel.MemberFilterViewModel

  test "the Period filter takes years and the rolling periods it offers" do
    for period <- ~w(all 2026 30d 60d 90d 180d 365d),
        do: assert({:ok, _, _} = MemberFilterViewModel.validate(%{"when" => period}, true))

    for period <- ~w(7d 90 d last-year),
        do: assert({:error, _} = MemberFilterViewModel.validate(%{"when" => period}, true))
  end

  # Away periods are often leave, so nothing in a member's URL may list, count, or sort
  # by them (#440). The params go before anything reads them.
  test "a member's params lose the filters, standings, and sort only team admins have" do
    params = %{
      "attended" => "90",
      "details" => "missing",
      "standing" => "active,away",
      "sort" => "standing-",
      "q" => "Sam"
    }

    assert {:ok, admin, _changeset} = MemberFilterViewModel.validate(params, true)
    assert {admin.attended, admin.details, admin.standing} == {"90", "missing", "active,away"}
    assert admin.sort == "standing-"

    assert {:ok, member, changeset} = MemberFilterViewModel.validate(params, false)
    assert {member.attended, member.details, member.standing} == {"all", "all", "current"}
    assert member.sort == "name"
    assert member.q == "Sam"
    assert changeset.changes == %{q: "Sam"}

    for standing <- ~w(active away not_a_person) do
      assert {:ok, %{standing: "current"}, _} =
               MemberFilterViewModel.validate(%{"standing" => standing}, false)
    end

    for standing <- ~w(current retired all) do
      assert {:ok, %{standing: ^standing}, _} =
               MemberFilterViewModel.validate(%{"standing" => standing}, false)
    end
  end

  test "a member's Standing switch and menu offer Not retired, Retired, and All" do
    assert MemberFilterViewModel.standing_switch(false) ==
             [{"Not retired", "current"}, {"Retired", "retired"}]

    assert MemberFilterViewModel.standing_kinds("all", false) ==
             [{"Not retired", "current"}, {"Retired", "retired"}, {"All", "all"}]

    refute MemberFilterViewModel.switch_standing?("active", false)
    assert MemberFilterViewModel.switch_standing?("active", true)
  end
end

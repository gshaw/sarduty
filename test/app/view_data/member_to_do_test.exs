defmodule App.ViewData.MemberToDoTest do
  use ExUnit.Case, async: true

  alias App.ViewData.MemberToDo

  @now ~U[2026-10-20 19:00:00Z]
  # Letter season, January to April.
  @in_season ~U[2026-03-10 19:00:00Z]
  @tz "America/Vancouver"
  @card %{id: 1}

  defp letter(year, downloaded_at \\ nil),
    do: %{id: year, year: year, downloaded_at: downloaded_at}

  defp row(status, title, days_left),
    do: %{status: status, award: %{qualification: %{title: title}}, days_left: days_left}

  defp keys(items), do: Enum.map(items, & &1.key)

  test "the card stays until it's in Wallet, and a member with no card has no item" do
    assert keys(MemberToDo.items(@card, false, [], [], @now, @tz)) == [:card]
    assert MemberToDo.items(@card, true, [], [], @now, @tz) == []
    assert MemberToDo.items(nil, false, [], [], @now, @tz) == []
  end

  test "each qualification expiring within 60 days, with its days left" do
    rows = [
      row(:expiring, "First Aid", 41),
      row(:expiring, "Radio", 1),
      row(:current, "Swiftwater", 132),
      row(:expired, "Rope", -750)
    ]

    assert [%{days: 41}, %{days: 1}] = MemberToDo.items(nil, false, [], rows, @now, @tz)
  end

  test "the newest letter until downloaded, and only last year's or this year's" do
    assert [%{key: :letter, letter: %{year: 2025}}] =
             MemberToDo.items(nil, false, [letter(2024), letter(2025)], [], @in_season, @tz)

    downloaded = [letter(2025, @in_season), letter(2024)]
    assert MemberToDo.items(nil, false, downloaded, [], @in_season, @tz) == []
    assert MemberToDo.items(nil, false, [letter(2023)], [], @in_season, @tz) == []
  end

  test "the letter only in letter season, January to April" do
    assert MemberToDo.items(nil, false, [letter(2025)], [], @now, @tz) == []
  end

  test "items come card, qualifications, then the letter" do
    rows = [row(:expiring, "First Aid", 41)]
    items = MemberToDo.items(@card, false, [letter(2025)], rows, @in_season, @tz)
    assert keys(items) == [:card, :qualification, :letter]
  end

  test "declined chores are one item until the member deletes them" do
    chores = [
      %{status: :declined, id: 1},
      %{status: :accepted, id: 2},
      %{status: :declined, id: 3}
    ]

    assert [%{key: :declined_chores, chores: [%{id: 1}, %{id: 3}]}] =
             MemberToDo.items(nil, false, [], [], @now, @tz, chores)

    assert MemberToDo.items(nil, false, [], [], @now, @tz, [%{status: :waiting, id: 4}]) == []
  end
end

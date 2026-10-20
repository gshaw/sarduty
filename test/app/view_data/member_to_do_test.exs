defmodule App.ViewData.MemberToDoTest do
  use ExUnit.Case, async: true

  alias App.ViewData.MemberToDo

  @now ~U[2026-10-20 19:00:00Z]
  @tz "America/Vancouver"
  @card %{id: 1}

  defp letter(year, downloaded_at \\ nil),
    do: %{id: year, year: year, downloaded_at: downloaded_at}

  defp keys(items), do: Enum.map(items, & &1.key)

  test "the card stays until it's in Wallet, and a member with no card has no item" do
    assert keys(MemberToDo.items(@card, false, [], [], @now, @tz)) == [:card]
    assert MemberToDo.items(@card, true, [], [], @now, @tz) == []
    assert MemberToDo.items(nil, false, [], [], @now, @tz) == []
  end

  test "each qualification expiring within 60 days, with the days left rounded up" do
    groups = [
      within_60_days: [
        %{award: %{qualification: %{title: "First Aid"}, ends_at: ~U[2026-11-30 12:00:00Z]}},
        %{award: %{qualification: %{title: "Radio"}, ends_at: ~U[2026-10-21 07:00:00Z]}}
      ],
      within_180_days: [
        %{award: %{qualification: %{title: "Swiftwater"}, ends_at: ~U[2027-03-01 00:00:00Z]}}
      ],
      expired: [%{award: %{qualification: %{title: "Rope"}, ends_at: ~U[2024-09-30 00:00:00Z]}}]
    ]

    assert [%{days: 41}, %{days: 1}] = MemberToDo.items(nil, false, [], groups, @now, @tz)
  end

  test "the newest letter until downloaded, and only last year's or this year's" do
    assert [%{key: :letter, letter: %{year: 2025}}] =
             MemberToDo.items(nil, false, [letter(2024), letter(2025)], [], @now, @tz)

    assert MemberToDo.items(nil, false, [letter(2025, @now), letter(2024)], [], @now, @tz) == []
    assert MemberToDo.items(nil, false, [letter(2023)], [], @now, @tz) == []
  end

  test "items come card, qualifications, then the letter" do
    groups = [
      within_60_days: [
        %{award: %{qualification: %{title: "First Aid"}, ends_at: ~U[2026-11-30 12:00:00Z]}}
      ]
    ]

    items = MemberToDo.items(@card, false, [letter(2025)], groups, @now, @tz)
    assert keys(items) == [:card, :qualification, :letter]
  end
end

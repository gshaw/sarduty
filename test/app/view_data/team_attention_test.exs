defmodule App.ViewData.TeamAttentionTest do
  use ExUnit.Case, async: true

  alias App.ViewData.TeamAttention

  # 9 a.m. on October 6 in Vancouver: not letter season.
  @october ~U[2026-10-06 16:00:00Z]
  # 9 a.m. on March 2 in Vancouver.
  @march ~U[2026-03-02 17:00:00Z]

  defp rows(attrs) do
    Map.merge(
      %{
        timezone: "America/Vancouver",
        service: :d4h,
        refresh: %{state: :ok, message: nil},
        draft_count: 0,
        expiring_days: 60,
        expiring_count: 0,
        missing_details_count: 0,
        not_seen: nil,
        group_change_count: 0,
        proposed_change_count: 0,
        chore_count: 0,
        chores_to_send: 0,
        untagged: [],
        letters: nil
      },
      attrs
    )
  end

  # The items for these counts, with every other count at zero.
  defp items(attrs, now), do: attrs |> rows() |> TeamAttention.items(now)

  defp keys(items), do: Enum.map(items, & &1.key)

  test "nothing to do means no items" do
    assert items(%{}, @october) == []
    assert items(%{untagged: [%{count: 0, year: 2026}]}, @october) == []
  end

  test "waiting chores ask a team admin to accept them" do
    assert [item] = items(%{chore_count: 3}, @october)
    assert %{key: :chores, level: :info, title: "3 chores to accept"} = item
  end

  test "a chore activity whose send did not go through is a warning" do
    assert [%{key: :chores_to_send, level: :warning} = item] =
             items(%{chores_to_send: 2}, @october)

    assert item.title == "2 chore activities out of date in D4H"
  end

  test "members not at an activity name the team's time frame" do
    assert items(%{not_seen: %{days: 90, count: 0}}, @october) == []

    row = %{days: 90, count: 3, group: nil, params: %{}}
    assert [item] = items(%{not_seen: row}, @october)
    assert item.key == :not_seen
    assert item.title == "3 members have not attended an activity in 90 days"

    assert [item] = items(%{not_seen: %{row | days: 365, count: 1}}, @october)
    assert item.title == "1 member has not attended an activity in a year"
  end

  test "members not at an activity name the watched group (#366)" do
    row = %{days: 90, count: 4, group: "Callout", params: %{}}
    assert [item] = items(%{not_seen: row}, @october)
    assert item.title == "4 members of Callout have not attended an activity in 90 days"

    assert [item] = items(%{not_seen: %{row | count: 1}}, @october)
    assert item.title == "1 member of Callout has not attended an activity in 90 days"
  end

  test "a watched group gone from D4H is a warning, never everyone (#366)" do
    assert [item] = items(%{not_seen: %{days: 90, missing_group: true}}, @october)
    assert item.key == :watch_missing
    assert item.level == :warning
    assert item.title == "The group you watch is no longer in D4H"
  end

  test "activities with no hours tag name the year" do
    assert [item] = items(%{untagged: [%{count: 12, year: 2026}]}, @october)
    assert item.key == :untagged
    assert item.year == 2026
    assert item.title == "12 activities in 2026 have no hours tag"
  end

  test "in letter season last year's activities with no hours tag show too" do
    untagged = [%{count: 4, year: 2025}, %{count: 1, year: 2026}]
    items = items(%{untagged: untagged}, @march)

    assert keys(items) == [:untagged_last_year, :untagged]
    assert hd(items).title == "4 activities in 2025 have no hours tag"
  end

  test "each count shows its item, warnings first" do
    items =
      items(
        %{
          group_change_count: 2,
          missing_details_count: 9,
          expiring_count: 6,
          draft_count: 3,
          refresh: %{state: :failed, message: "D4H rejected the team key (401)."}
        },
        @october
      )

    assert keys(items) == [:refresh, :drafts, :expiring, :missing_details, :group_changes]
    assert Enum.map(items, & &1.level) == [:warning, :warning, :warning, :info, :info]
  end

  test "titles carry the count, with the noun agreeing" do
    one = items(%{draft_count: 1, missing_details_count: 1}, @october)
    many = items(%{draft_count: 3, missing_details_count: 9}, @october)

    assert Enum.map(one, & &1.title) == [
             "1 draft activity",
             "1 member has no email or mobile phone"
           ]

    assert Enum.map(many, & &1.title) == [
             "3 draft activities",
             "9 members have no email or mobile phone"
           ]

    assert [%{title: "6 qualifications expire within 60 days"}] =
             items(%{expiring_count: 6}, @october)
  end

  test "a failed refresh shows D4H's reason; a rejected key alone says so too" do
    failed = %{refresh: %{state: :failed, message: "No D4H key."}}
    assert [%{key: :refresh, detail: "No D4H key."}] = items(failed, @october)

    rejected = %{refresh: %{state: :key_rejected, message: nil}}
    assert [%{key: :refresh, detail: detail}] = items(rejected, @october)
    assert detail == "Your D4H access key no longer works."

    assert items(%{refresh: %{state: :refreshing, message: nil}}, @october) ==
             []
  end

  test "tax credit letters show from January to April only, in the team's zone" do
    letters = %{letters: %{year: 2025, count: 11}}

    assert [%{key: :letters, year: 2025, title: "11 tax credit letters to create for 2025"}] =
             items(letters, @march)

    assert items(letters, @october) == []
    # 5 p.m. on April 30 in Vancouver, already May 1 in UTC.
    assert [%{key: :letters}] = items(letters, ~U[2026-05-01 00:30:00Z])
    assert items(%{letters: %{year: 2025, count: 0}}, @march) == []
  end

  test "every item can show at once" do
    everything =
      %{
        refresh: %{state: :failed, message: "No D4H key."},
        draft_count: 1,
        expiring_count: 1,
        missing_details_count: 1,
        group_change_count: 1,
        proposed_change_count: 1,
        letters: %{year: 2025, count: 1}
      }

    assert everything |> items(@march) |> length() == 7
  end

  test "a team on SAR Duty Records hears about Records, not D4H" do
    attrs = %{
      service: :records,
      refresh: %{state: :key_rejected},
      proposed_change_count: 2,
      missing_details_count: 3,
      draft_count: 2,
      expiring_count: 1
    }

    for item <- items(attrs, @october) do
      refute item.title =~ "D4H", item.title
      refute item.detail =~ "D4H", item.title
    end

    assert [%{title: "SAR Duty cannot refresh from SAR Duty Records"} | _] =
             items(attrs, @october)
  end
end

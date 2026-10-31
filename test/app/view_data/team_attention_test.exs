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
        names: %{name: "Ridge SAR", abbreviated_name: "RIDGE"},
        contacts?: true,
        draft_ids: [],
        missing_fields_ids: [],
        expiring_days: 60,
        expiring_ids: [],
        missing_details_ids: [],
        not_seen: nil,
        retiring: nil,
        group_change_count: 0,
        chore_count: 0,
        certificate_count: 0,
        chores_to_send: 0,
        attendance_to_send: [],
        no_shows: [],
        untagged: [],
        two_hours_tags: [],
        letters: nil
      },
      attrs
    )
  end

  # The items shown for these counts, with every other count at zero.
  defp items(attrs, now), do: attrs |> rows() |> TeamAttention.items(now) |> Map.fetch!(:shown)

  defp keys(items), do: Enum.map(items, & &1.key)

  # `count` made-up ids, for an item that counts them.
  defp ids(count), do: Enum.to_list(1..count//1)

  describe "snoozing (#751)" do
    # Blake, Dana, and Drew hold items; Sam is new.
    @holding %{holding: 3, items: 7, holding_ids: [1, 2, 3], clear_ids: [], d4h_access: 0}

    defp snooze(attrs),
      do: Map.merge(%{key: "retiring", ids: [1, 2, 3], until: ~U[2026-10-13 16:00:00Z]}, attrs)

    defp split(retiring, snoozes, limit \\ 7),
      do: %{retiring: retiring} |> rows() |> TeamAttention.items(@october, snoozes, limit)

    test "hides the item and carries its snooze" do
      snooze = snooze(%{})

      assert %{shown: [], snoozed: [%{key: :retiring, snooze: ^snooze}]} =
               split(@holding, [snooze])
    end

    test "stays hidden as members leave the item" do
      row = %{@holding | holding: 2, holding_ids: [1, 3]}
      assert %{shown: [], snoozed: [_item]} = split(row, [snooze(%{})])
    end

    test "comes back when someone new is behind it" do
      row = %{@holding | holding: 3, holding_ids: [1, 2, 4]}
      assert %{shown: [%{key: :retiring}], snoozed: []} = split(row, [snooze(%{})])
    end

    test "comes back when the snooze ends" do
      snooze = snooze(%{until: @october})
      assert %{shown: [%{key: :retiring}], snoozed: []} = split(@holding, [snooze])
    end

    test "is only for items with ids" do
      row = %{@holding | d4h_access: 2}
      snoozes = [snooze(%{}), snooze(%{key: "retiring_access", ids: [1, 2, 3]})]
      %{shown: [access], snoozed: [_retiring]} = split(row, snoozes)

      assert access.key == :retiring_access
      refute TeamAttention.can_snooze?(access)
    end

    # The rule in TeamAttention's moduledoc: can_snooze when it waits on people outside SAR
    # Duty, never when it is broken, one step in SAR Duty, leaves on its own, or has a
    # deadline. A new item lands in one list or the other here.
    test "every item that waits on people can be snoozed, and says what brings it back" do
      everything =
        rows(%{
          refresh: %{state: :failed, message: "No D4H key."},
          draft_ids: ids(2),
          missing_fields_ids: ids(1),
          expiring_ids: ids(3),
          missing_details_ids: ids(4),
          not_seen: %{days: 90, ids: ids(5), group: nil, params: %{}},
          retiring: %{@holding | clear_ids: [5], d4h_access: 1},
          group_change_count: 1,
          chore_count: 1,
          certificate_count: 1,
          chores_to_send: 1,
          attendance_to_send: [%{id: 1, title: "Training"}],
          no_shows: [%{id: 2, title: "Rope", count: 1}],
          untagged: [%{count: 1, year: 2025, ids: [7]}, %{count: 1, year: 2026, ids: [8]}],
          two_hours_tags: [
            %{year: 2025, primary: 1, secondary: 0, ids: [9]},
            %{year: 2026, primary: 0, secondary: 1, ids: [10]}
          ],
          letters: %{year: 2025, count: 1},
          names: %{name: String.duplicate("a", 21), abbreviated_name: String.duplicate("a", 11)},
          contacts?: false
        })

      %{shown: items} = TeamAttention.items(everything, @march, [], :all)
      {can_snooze, cannot_snooze} = Enum.split_with(items, &TeamAttention.can_snooze?/1)

      assert can_snooze |> keys() |> Enum.sort() ==
               Enum.sort(~w(drafts missing_fields expiring missing_details not_seen retiring
                            retiring_clear untagged two_hours_tags)a)

      assert cannot_snooze |> keys() |> Enum.sort() ==
               Enum.sort(~w(refresh retiring_access group_changes chores certificates
                            chores_to_send attendance_to_send no_shows untagged_last_year
                            two_hours_tags_last_year letters long_name
                            long_abbreviated_name team_contacts)a)

      for item <- can_snooze do
        assert TeamAttention.back_sooner(item) =~ ~r/^It comes back sooner if another .+\.$/
        assert item.ids == Enum.sort(item.ids)
      end
    end

    test "a snoozed draft stays hidden as drafts are published, and comes back for a new one" do
      snooze = snooze(%{key: "drafts", ids: [1, 2, 3]})
      assert %{shown: []} = split_rows(%{draft_ids: [2, 3]}, [snooze])
      assert %{shown: [%{key: :drafts}]} = split_rows(%{draft_ids: [2, 3, 4]}, [snooze])
    end

    defp split_rows(attrs, snoozes), do: attrs |> rows() |> TeamAttention.items(@october, snoozes)

    test "frees its place for the next item" do
      row = %{@holding | clear_ids: [5]}
      assert %{shown: [%{key: :retiring_clear}]} = split(row, [snooze(%{})], 1)
    end
  end

  test "nothing to do means no items" do
    assert items(%{}, @october) == []
    assert items(%{untagged: [%{count: 0, year: 2026, ids: ids(0)}]}, @october) == []
  end

  describe "names (#738)" do
    test "a name too long for ID cards asks for a shorter one" do
      names = %{name: "York Sunbury Search and Rescue", abbreviated_name: "YSSR"}
      assert [item] = items(%{names: names}, @october)
      assert %{key: :long_name, level: :info} = item
      assert item.title == "Your team's name is too long for ID cards"
      assert item.detail =~ ~s("York Sunbury Search and Rescue" is cut off)
      assert item.detail =~ "20 characters or fewer"
    end

    test "an abbreviated name too long for texts asks for a shorter one" do
      names = %{name: "York Sunbury SAR", abbreviated_name: "York Sunbury SAR"}

      assert [%{key: :long_abbreviated_name, level: :info} = item] =
               items(%{names: names}, @october)

      assert item.detail =~ "10 characters or fewer"
    end

    test "names at the advised lengths need nothing" do
      names = %{name: String.duplicate("a", 20), abbreviated_name: String.duplicate("a", 10)}
      assert items(%{names: names}, @october) == []
    end
  end

  test "waiting chores ask a team admin to accept them" do
    assert [item] = items(%{chore_count: 3}, @october)
    assert %{key: :chores, level: :info, title: "3 chores to accept"} = item
  end

  test "waiting certificates ask a team admin to accept them" do
    assert [item] = items(%{certificate_count: 1}, @october)
    assert %{key: :certificates, level: :info, title: "1 certificate to accept"} = item
  end

  test "a chore activity whose send did not go through is a warning" do
    assert [%{key: :chores_to_send, level: :warning} = item] =
             items(%{chores_to_send: 2}, @october)

    assert item.title == "2 chore activities out of date"
  end

  describe "attendance to send (#475)" do
    @training %{id: 7, title: "Training night"}
    @rope %{id: 8, title: "Rope practice"}

    test "one activity is named in the title and opens" do
      item = TeamAttention.attendance_to_send_item([@training])

      assert %{key: :attendance_to_send, level: :info, activity_id: 7} = item
      assert item.title == "Attendance to send: Training night"
      assert item.detail == "Review the changes, then send them."
    end

    test "several are counted, and the oldest is named and opens" do
      item = TeamAttention.attendance_to_send_item([@training, @rope])

      assert item.title == "Attendance to send for 2 activities"
      assert item.detail == "The oldest is Training night."
      assert item.activity_id == 7
    end

    test "none means no item" do
      assert TeamAttention.attendance_to_send_item([]) == nil
      refute :attendance_to_send in keys(items(%{}, @october))
      assert :attendance_to_send in keys(items(%{attendance_to_send: [@rope]}, @october))
    end
  end

  describe "no-shows to follow up (#650)" do
    @mit %{id: 7, title: "MIT training", count: 3}
    @rope_night %{id: 8, title: "Rope practice", count: 2}

    test "one activity is named in the title and opens" do
      item = TeamAttention.no_shows_item([@mit])

      assert %{key: :no_shows, level: :info, activity_id: 7, action: "Follow up"} = item
      assert item.title == "3 no-shows to follow up: MIT training"
      assert item.detail == "Check each one is OK, then mark them followed up."
    end

    test "several are counted, and the oldest is named and opens" do
      item = TeamAttention.no_shows_item([@mit, @rope_night])

      assert item.title == "5 no-shows to follow up from 2 activities"
      assert item.detail == "The oldest is MIT training."
      assert item.activity_id == 7
    end

    test "none means no item" do
      assert TeamAttention.no_shows_item([]) == nil
      refute :no_shows in keys(items(%{}, @october))
      assert :no_shows in keys(items(%{no_shows: [@mit]}, @october))
    end
  end

  test "members not at an activity name the team's time frame" do
    assert items(%{not_seen: %{days: 90, ids: []}}, @october) == []

    row = %{days: 90, ids: ids(3), group: nil, params: %{}}
    assert [item] = items(%{not_seen: row}, @october)
    assert item.key == :not_seen
    assert item.title == "3 members have not attended an activity in 90 days"

    assert [item] = items(%{not_seen: %{row | days: 365, ids: ids(1)}}, @october)
    assert item.title == "1 member has not attended an activity in a year"
  end

  test "members not at an activity name the watched group (#366)" do
    row = %{days: 90, ids: ids(4), group: "Callout", params: %{}}
    assert [item] = items(%{not_seen: row}, @october)
    assert item.title == "4 members of Callout have not attended an activity in 90 days"

    assert [item] = items(%{not_seen: %{row | ids: ids(1)}}, @october)
    assert item.title == "1 member of Callout has not attended an activity in 90 days"
  end

  test "a watched group gone from D4H is a warning, never everyone (#366)" do
    assert [item] = items(%{not_seen: %{days: 90, missing_group: true}}, @october)
    assert item.key == :watch_missing
    assert item.level == :warning
    assert item.title == "The group you watch was deleted"
  end

  test "activities with no hours tag name the year" do
    assert [item] = items(%{untagged: [%{count: 12, year: 2026, ids: ids(12)}]}, @october)
    assert item.key == :untagged
    assert item.year == 2026
    assert item.title == "12 activities in 2026 have no hours tag"
  end

  test "in letter season last year's activities with no hours tag show too" do
    untagged = [%{count: 4, year: 2025, ids: ids(4)}, %{count: 1, year: 2026, ids: ids(1)}]
    items = items(%{untagged: untagged}, @march)

    assert keys(items) == [:untagged_last_year, :untagged]
    assert hd(items).title == "4 activities in 2025 have no hours tag"
  end

  describe "two hours tags (#763)" do
    test "say which hours letters count and where to fix them" do
      row = %{year: 2026, primary: 2, secondary: 0, ids: [3, 4]}
      assert [item] = items(%{two_hours_tags: [row]}, @october)
      assert %{key: :two_hours_tags, level: :info, year: 2026, ids: [3, 4]} = item
      assert item.title == "2 activities in 2026 have two hours tags"

      assert item.detail ==
               "Tax credit letters count primary hours for them. " <>
                 "Take each extra tag off with Change tags, or in D4H for a published one."
    end

    test "one counted as secondary on a Records team stays in SAR Duty" do
      rows = %{
        two_hours_tags: [%{year: 2026, primary: 0, secondary: 1, ids: [5]}],
        service: :records
      }

      assert [item] = items(rows, @october)
      assert item.title == "1 activity in 2026 has two hours tags"

      assert item.detail ==
               "Tax credit letters count secondary hours for it. " <>
                 "Take the extra tag off with Change tags."
    end

    test "a mix names both counts" do
      assert [item] =
               items(
                 %{two_hours_tags: [%{year: 2026, primary: 2, secondary: 1, ids: [1, 2, 3]}]},
                 @october
               )

      assert item.title == "3 activities in 2026 have two hours tags"
      assert item.detail =~ "count primary hours for 2 and secondary hours for 1."
    end

    test "in letter season last year's show too, and none means no item" do
      rows = [
        %{year: 2025, primary: 1, secondary: 0, ids: [1]},
        %{year: 2026, primary: 0, secondary: 0, ids: []}
      ]

      assert keys(items(%{two_hours_tags: rows}, @march)) == [:two_hours_tags_last_year]
    end
  end

  test "each count shows its item, warnings first" do
    items =
      items(
        %{
          group_change_count: 2,
          missing_details_ids: ids(9),
          expiring_ids: ids(6),
          draft_ids: ids(3),
          refresh: %{state: :failed, message: "D4H rejected the team key (401)."}
        },
        @october
      )

    assert keys(items) == [:refresh, :drafts, :expiring, :missing_details, :group_changes]
    assert Enum.map(items, & &1.level) == [:warning, :warning, :warning, :info, :info]
  end

  test "titles carry the count, with the noun agreeing" do
    one = items(%{draft_ids: ids(1), missing_details_ids: ids(1)}, @october)
    many = items(%{draft_ids: ids(3), missing_details_ids: ids(9)}, @october)

    assert Enum.map(one, & &1.title) == [
             "1 draft activity",
             "1 member has no email, mobile phone, or address"
           ]

    assert Enum.map(many, & &1.title) == [
             "3 draft activities",
             "9 members have no email, mobile phone, or address"
           ]

    assert [%{title: "6 awards expire within 60 days"}] =
             items(%{expiring_ids: ids(6)}, @october)
  end

  test "a failed refresh shows D4H's reason; a rejected key alone says so too" do
    failed = %{refresh: %{state: :failed, message: "No D4H key."}}
    assert [%{key: :refresh, detail: "No D4H key."}] = items(failed, @october)

    rejected = %{refresh: %{state: :key_rejected, message: nil}}
    assert [%{key: :key_rejected, detail: detail}] = items(rejected, @october)
    assert detail == "Your D4H access key no longer works."

    assert items(%{refresh: %{state: :refreshing, message: nil}}, @october) ==
             []
  end

  test "tax credit letters show from January to April only, in the team's zone" do
    letters = %{letters: %{year: 2025, count: 11}}

    assert [%{key: :letters, year: 2025, title: "11 tax credit letters to send for 2025"}] =
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
        draft_ids: ids(1),
        expiring_ids: ids(1),
        missing_details_ids: ids(1),
        group_change_count: 1,
        letters: %{year: 2025, count: 1}
      }

    assert everything |> items(@march) |> length() == 6
  end

  test "past 7, the rest wait in more, in order; an agent gets them all" do
    nine =
      rows(%{
        draft_ids: ids(1),
        missing_fields_ids: ids(1),
        expiring_ids: ids(1),
        missing_details_ids: ids(1),
        group_change_count: 1,
        chore_count: 1,
        certificate_count: 1,
        chores_to_send: 1,
        attendance_to_send: [%{id: 1, title: "Training"}]
      })

    %{shown: all, more: []} = TeamAttention.items(nine, @october, [], :all)
    %{shown: shown, more: more} = TeamAttention.items(nine, @october)

    assert length(all) == 9
    assert {shown, more} == Enum.split(all, 7)

    snooze = %{key: "drafts", ids: [1], until: ~U[2026-10-13 16:00:00Z]}
    assert %{more: [_last]} = TeamAttention.items(nine, @october, [snooze])
  end

  test "a team on SAR Duty Records hears about Records, not D4H" do
    attrs = %{
      service: :records,
      refresh: %{state: :key_rejected},
      missing_details_ids: ids(3),
      draft_ids: ids(2),
      expiring_ids: ids(1)
    }

    for item <- items(attrs, @october) do
      refute item.title =~ "D4H", item.title
      refute item.detail =~ "D4H", item.title
    end

    assert [%{title: "SAR Duty cannot refresh from SAR Duty Records"} | _] =
             items(attrs, @october)
  end

  test "drafts missing required fields (#681)" do
    assert [item] = items(%{missing_fields_ids: ids(2)}, @october)
    assert item.key == :missing_fields
    assert item.level == :warning
    assert item.title == "2 draft activities are missing required fields"
    assert item.detail == "D4H won't publish them until they're filled in."

    assert [%{title: "1 draft activity is missing required fields"}] =
             items(%{missing_fields_ids: ids(1)}, @october)
  end
end

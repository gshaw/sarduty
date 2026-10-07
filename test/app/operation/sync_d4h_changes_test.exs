defmodule App.Operation.SyncD4HChangesTest do
  use ExUnit.Case, async: true

  alias App.Operation.SyncD4HChanges

  @lists ~w(members tags exercises events incidents attendance member-qualifications
            member-qualification-awards member-groups member-group-memberships)

  defp heads(overrides \\ %{}) do
    @lists
    |> Map.new(&{&1, %{total_size: 10, newest_updated_at: ~U[2026-10-05 12:00:00Z]}})
    |> Map.merge(overrides)
  end

  defp moved(at \\ ~U[2026-10-06 09:00:00Z]), do: %{total_size: 10, newest_updated_at: at}

  test "with no previous look, it only records the heads" do
    assert SyncD4HChanges.plan(nil, heads()) == :seed
  end

  test "when no head moved, there is nothing to fetch" do
    assert SyncD4HChanges.plan(heads(), heads()) == :unchanged
  end

  test "a changed small list is fetched whole, with the lists that point at it" do
    plan = SyncD4HChanges.plan(heads(), heads(%{"members" => moved()}))

    assert plan.changed == ["members"]
    assert plan.lists == ["members", "member-qualification-awards", "member-group-memberships"]
    assert plan.activities == %{}
    assert plan.attendance_since == nil
  end

  test "lists are fetched in the order their rows depend on" do
    changed = %{"member-group-memberships" => moved(), "member-groups" => moved()}
    plan = SyncD4HChanges.plan(heads(), heads(changed))

    assert plan.lists == ["member-groups", "member-group-memberships"]
  end

  test "activities and attendance are fetched from the last newest change, less 5 minutes" do
    changed = %{"events" => moved(), "attendance" => %{total_size: 9, newest_updated_at: nil}}
    plan = SyncD4HChanges.plan(heads(), heads(changed))

    assert plan.activities == %{
             "events" => %{
               updated_after: ~U[2026-10-05 11:55:00Z],
               compare_ids?: true,
               touch?: true
             }
           }

    assert plan.attendance_since == ~U[2026-10-05 11:55:00Z]
  end

  test "a delete alone moves the total, and still compares ids to find it" do
    previous = heads()
    now = heads(%{"incidents" => %{previous["incidents"] | total_size: 9}})

    assert %{"incidents" => %{compare_ids?: true}} =
             SyncD4HChanges.plan(previous, now).activities
  end

  test "a tag change refetches every activity, without touching their attendance" do
    plan = SyncD4HChanges.plan(heads(), heads(%{"tags" => moved()}))

    assert Map.keys(plan.activities) == ["events", "exercises", "incidents"]

    for {_kind, cursors} <- plan.activities do
      assert cursors.updated_after == ~U[2000-01-01 00:00:00Z]
      refute cursors.compare_ids?
      refute cursors.touch?
    end
  end

  test "a list that was empty last time is fetched from the start" do
    previous = heads(%{"events" => %{total_size: 0, newest_updated_at: nil}})
    plan = SyncD4HChanges.plan(previous, heads(%{"events" => moved()}))

    assert plan.activities["events"].updated_after == ~U[2000-01-01 00:00:00Z]
  end

  describe "count windows" do
    test "a window per year, Jan 1 to Jan 1" do
      assert SyncD4HChanges.year_windows(2025, 2026) == [
               {~U[2025-01-01 00:00:00Z], ~U[2026-01-01 00:00:00Z]},
               {~U[2026-01-01 00:00:00Z], ~U[2027-01-01 00:00:00Z]}
             ]
    end

    test "a window per month of a year, December ending on next Jan 1" do
      months = SyncD4HChanges.month_windows({~U[2026-01-01 00:00:00Z], ~U[2027-01-01 00:00:00Z]})

      assert length(months) == 12
      assert hd(months) == {~U[2026-01-01 00:00:00Z], ~U[2026-02-01 00:00:00Z]}
      assert List.last(months) == {~U[2026-12-01 00:00:00Z], ~U[2027-01-01 00:00:00Z]}
    end

    test "only windows whose counts differ, in order" do
      windows = SyncD4HChanges.year_windows(2024, 2026)
      [y2024, y2025, y2026] = windows
      local = %{y2024 => 5, y2025 => 7}
      d4h = %{y2024 => 5, y2025 => 6, y2026 => 1}

      assert SyncD4HChanges.windows_to_check(windows, local, d4h) == [y2025, y2026]
    end
  end
end

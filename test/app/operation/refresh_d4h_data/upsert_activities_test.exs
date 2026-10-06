defmodule App.Operation.RefreshD4HData.UpsertActivitiesTest do
  use App.DataCase

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.ShortLink
  alias App.Operation.CreateAttendanceLink
  alias App.Operation.RefreshD4HData.UpsertActivities

  @now ~U[2026-10-06 06:00:00.000000Z]

  test "marks this team's activities of one kind that D4H no longer lists" do
    team = team_fixture()
    listed = activity_fixture(team, %{activity_kind: "event"})
    missing = activity_fixture(team, %{activity_kind: "event"})
    exercise = activity_fixture(team, %{activity_kind: "exercise"})
    other_team = activity_fixture(team_fixture(), %{activity_kind: "event"})

    UpsertActivities.mark_deleted(team, "event", MapSet.new([listed.d4h_activity_id]), @now)

    assert Repo.get(Activity, listed.id).deleted_at == nil
    assert Repo.get(Activity, missing.id).deleted_at == ~U[2026-10-06 06:00:00Z]
    assert Repo.get(Activity, exercise.id).deleted_at == nil
    assert Repo.get(Activity, other_team.id).deleted_at == nil
  end

  test "closes the attendance link of a deleted activity" do
    team = team_fixture()
    activity = activity_fixture(team, %{activity_kind: "event"})
    kept = activity_fixture(team, %{activity_kind: "event"})
    link = CreateAttendanceLink.call(team, activity, user_fixture(), DateTime.utc_now())
    kept_link = CreateAttendanceLink.call(team, kept, user_fixture(), DateTime.utc_now())

    UpsertActivities.mark_deleted(team, "event", MapSet.new([kept.d4h_activity_id]), @now)

    assert Repo.reload(link).closed_at == @now
    refute Repo.get(ShortLink, link.short_link_id)
    assert Repo.reload(kept_link).closed_at == nil
    assert AttendanceLink.find_current(team, kept)
  end

  test "clears the mark when D4H lists the activity again" do
    team = team_fixture()
    activity = activity_fixture(team, %{deleted_at: ~U[2026-10-01 06:00:00Z]})

    UpsertActivities.mark_deleted(
      team,
      activity.activity_kind,
      MapSet.new([activity.d4h_activity_id]),
      @now
    )

    assert Repo.get(Activity, activity.id).deleted_at == nil
  end
end

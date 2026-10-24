defmodule App.Operation.RefreshD4HData.UpsertActivitiesTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Activity
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

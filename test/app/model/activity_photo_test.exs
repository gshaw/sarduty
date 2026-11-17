defmodule App.Model.ActivityPhotoTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.ActivityPhoto

  # Who sees an activity's photo (#1032): an accepted one, everyone on the team; a
  # waiting one, team admins and the member who added it, and nobody else.
  setup do
    team = team_fixture(%{photos_enabled: true})
    activity = activity_fixture(team)
    adder = member_fixture(team)
    other = member_fixture(team)

    %{
      team: team,
      activity: activity,
      adder: adder,
      other: other,
      waiting: activity_photo_fixture(activity, %{member_id: adder.id}),
      accepted: activity_photo_fixture(activity, %{member_id: adder.id, status: :accepted})
    }
  end

  defp ids(photos), do: photos |> Enum.map(& &1.id) |> Enum.sort()

  defp viewers(ctx) do
    %{
      team_admin: %{team_admin?: true, member: nil},
      adder: %{team_admin?: false, member: ctx.adder},
      other: %{team_admin?: false, member: ctx.other},
      nobody: %{team_admin?: false, member: nil}
    }
  end

  test "for_activity/2 lists a waiting photo only for a team admin and who added it", ctx do
    both = ids([ctx.waiting, ctx.accepted])
    viewers = viewers(ctx)

    assert ctx.activity |> ActivityPhoto.for_activity(viewers.team_admin) |> ids() == both
    assert ctx.activity |> ActivityPhoto.for_activity(viewers.adder) |> ids() == both
    assert ctx.activity |> ActivityPhoto.for_activity(viewers.other) |> ids() == [ctx.accepted.id]

    assert ctx.activity |> ActivityPhoto.for_activity(viewers.nobody) |> ids() == [
             ctx.accepted.id
           ]
  end

  test "visible?/2 gives the same answer for one photo", ctx do
    for {_name, viewer} <- viewers(ctx), photo <- [ctx.waiting, ctx.accepted] do
      listed? = photo.id in ids(ActivityPhoto.for_activity(ctx.activity, viewer))
      assert ActivityPhoto.visible?(photo, viewer) == listed?
    end
  end

  test "find_visible!/3 finds a waiting photo only for a team admin and who added it", ctx do
    viewers = viewers(ctx)

    for viewer <- [viewers.team_admin, viewers.adder],
        do:
          assert(
            ActivityPhoto.find_visible!(ctx.team, ctx.waiting.id, viewer).id == ctx.waiting.id
          )

    for viewer <- [viewers.other, viewers.nobody] do
      assert_raise Ecto.NoResultsError, fn ->
        ActivityPhoto.find_visible!(ctx.team, ctx.waiting.id, viewer)
      end

      assert ActivityPhoto.find_visible!(ctx.team, ctx.accepted.id, viewer).id == ctx.accepted.id
    end
  end

  test "find_visible!/3 never finds another team's photo, even for a team admin", ctx do
    other_team = team_fixture(%{photos_enabled: true})

    assert_raise Ecto.NoResultsError, fn ->
      ActivityPhoto.find_visible!(other_team, ctx.accepted.id, %{team_admin?: true, member: nil})
    end
  end

  test "a deleted activity's photo is a team admin's only", ctx do
    ctx.activity |> Ecto.Changeset.change(deleted_at: ~U[2026-11-04 18:00:00Z]) |> Repo.update!()
    viewers = viewers(ctx)

    assert ActivityPhoto.find_visible!(ctx.team, ctx.accepted.id, viewers.team_admin)

    assert_raise Ecto.NoResultsError, fn ->
      ActivityPhoto.find_visible!(ctx.team, ctx.accepted.id, viewers.adder)
    end
  end

  # Never from an incident: an exercise the team's records turn into one keeps its
  # photos out of sight, for a team admin too.
  test "an activity that becomes an incident stops showing its photos", ctx do
    ctx.activity |> Ecto.Changeset.change(activity_kind: "incident") |> Repo.update!()
    team_admin = viewers(ctx).team_admin

    for photo <- [ctx.waiting, ctx.accepted] do
      assert_raise Ecto.NoResultsError, fn ->
        ActivityPhoto.find_visible!(ctx.team, photo.id, team_admin)
      end
    end

    assert ActivityPhoto.get_waiting(ctx.team) == []
    assert ActivityPhoto.count_waiting(ctx.team) == 0
  end

  test "get_waiting/1 and count_waiting/1: the team's waiting photos, by activity", ctx do
    later = activity_fixture(ctx.team, %{started_at: DateTime.add(ctx.activity.started_at, 3600)})
    newer = activity_photo_fixture(later)
    deleted = activity_fixture(ctx.team, %{deleted_at: ~U[2026-11-04 18:00:00Z]})
    activity_photo_fixture(deleted)
    activity_photo_fixture(activity_fixture(team_fixture()))

    # The later activity first. Never an accepted photo, a deleted activity's, or
    # another team's.
    assert ctx.team |> ActivityPhoto.get_waiting() |> Enum.map(& &1.id) == [
             newer.id,
             ctx.waiting.id
           ]

    assert ActivityPhoto.count_waiting(ctx.team) == 2
    assert ActivityPhoto.count_waiting_on(ctx.activity) == 1
  end

  test "key/2 names each file under the team's prefix", ctx do
    assert ActivityPhoto.key(ctx.waiting, :tile) ==
             "teams/#{ctx.team.id}/activity-photos/#{ctx.waiting.file_token}/tile.jpg"

    keys = for size <- ActivityPhoto.sizes(), do: ActivityPhoto.key(ctx.waiting, size)
    assert length(Enum.uniq(keys)) == 3
    assert ActivityPhoto.new_token() != ActivityPhoto.new_token()
  end
end

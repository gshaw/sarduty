defmodule App.Operation.AcceptActivityPhotosTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.ActivityPhoto
  alias App.Operation.AcceptActivityPhotos

  # A team admin accepts an activity's waiting photos (#1032). The ids come from the
  # browser, so only the team's, on this activity, and still waiting change.
  setup do
    team = team_fixture(%{photos_enabled: true})
    activity = activity_fixture(team)
    %{team: team, activity: activity, user: user_fixture(), now: ~U[2026-11-04 18:00:00.000000Z]}
  end

  defp status(photo), do: Repo.reload!(photo).status

  test "accepts the photos named, and says who and when", ctx do
    first = activity_photo_fixture(ctx.activity)
    second = activity_photo_fixture(ctx.activity)
    left = activity_photo_fixture(ctx.activity)

    assert AcceptActivityPhotos.call(
             ctx.team,
             ctx.activity,
             [first.id, second.id],
             ctx.user,
             ctx.now
           ) ==
             {:ok, 2}

    assert %ActivityPhoto{status: :accepted, accepted_at: at, accepted_by_user_id: by} =
             Repo.reload!(first)

    assert at == ctx.now
    assert by == ctx.user.id
    assert status(second) == :accepted
    assert status(left) == :waiting
  end

  test "leaves another activity's photos and another team's", ctx do
    elsewhere = activity_photo_fixture(activity_fixture(ctx.team))
    other_team = team_fixture(%{photos_enabled: true})
    theirs = activity_photo_fixture(activity_fixture(other_team))

    assert AcceptActivityPhotos.call(
             ctx.team,
             ctx.activity,
             [elsewhere.id, theirs.id],
             ctx.user,
             ctx.now
           ) == {:ok, 0}

    assert status(elsewhere) == :waiting
    assert status(theirs) == :waiting
  end

  test "a photo accepted already keeps who accepted it", ctx do
    first = user_fixture()
    photo = activity_photo_fixture(ctx.activity)
    {:ok, 1} = AcceptActivityPhotos.call(ctx.team, ctx.activity, [photo.id], first, ctx.now)

    later = DateTime.add(ctx.now, 60)

    assert AcceptActivityPhotos.call(ctx.team, ctx.activity, [photo.id], ctx.user, later) ==
             {:ok, 0}

    assert Repo.reload!(photo).accepted_by_user_id == first.id
  end
end

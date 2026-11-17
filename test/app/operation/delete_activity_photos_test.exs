defmodule App.Operation.DeleteActivityPhotosTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Operation.DeleteActivityPhotos

  # A team admin deletes an activity's waiting photos (#1032): the row and its three
  # files. The ids come from the browser, so only the team's, on this activity, and
  # still waiting go.
  setup do
    team = team_fixture(%{photos_enabled: true})
    %{team: team, activity: activity_fixture(team)}
  end

  defp kept?(photo) do
    files = activity_photo_files(photo)
    Repo.reload(photo) != nil and Enum.all?(files, &match?({:ok, _bytes}, &1))
  end

  defp gone?(photo) do
    files = activity_photo_files(photo)
    Repo.reload(photo) == nil and Enum.all?(files, &(&1 == {:error, :not_found}))
  end

  test "deletes the photos named, with their files, and leaves the rest", ctx do
    first = activity_photo_fixture(ctx.activity)
    second = activity_photo_fixture(ctx.activity)
    left = activity_photo_fixture(ctx.activity)

    assert DeleteActivityPhotos.call(ctx.team, ctx.activity, [first.id, second.id]) ==
             {:ok, %{deleted: 2, kept: 0}}

    assert gone?(first)
    assert gone?(second)
    assert kept?(left)
  end

  test "leaves another activity's photos and another team's", ctx do
    elsewhere = activity_photo_fixture(activity_fixture(ctx.team))
    other_team = team_fixture(%{photos_enabled: true})
    theirs = activity_photo_fixture(activity_fixture(other_team))

    assert DeleteActivityPhotos.call(ctx.team, ctx.activity, [elsewhere.id, theirs.id]) ==
             {:ok, %{deleted: 0, kept: 0}}

    assert kept?(elsewhere)
    assert kept?(theirs)
  end

  test "leaves an accepted photo: only waiting ones are deleted here", ctx do
    accepted = activity_photo_fixture(ctx.activity, %{status: :accepted})

    assert DeleteActivityPhotos.call(ctx.team, ctx.activity, [accepted.id]) ==
             {:ok, %{deleted: 0, kept: 0}}

    assert kept?(accepted)
  end
end

defmodule App.Operation.DeleteActivityPhotoTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.ActivityPhotoStar
  alias App.Operation.DeleteActivityPhoto
  alias App.Operation.StarActivityPhoto

  # A team admin deletes one activity photo (#1033): the row, its stars, and its three
  # files, for good, and only through its own team.
  setup do
    team = team_fixture(%{photos_enabled: true})
    activity = activity_fixture(team)
    photo = activity_photo_fixture(activity, %{status: :accepted})
    %{team: team, activity: activity, photo: photo}
  end

  defp stars(photo),
    do: ActivityPhotoStar |> where(activity_photo_id: ^photo.id) |> Repo.aggregate(:count)

  defp files_gone?(photo),
    do: photo |> activity_photo_files() |> Enum.all?(&(&1 == {:error, :not_found}))

  defp files_kept?(photo),
    do: photo |> activity_photo_files() |> Enum.all?(&match?({:ok, _bytes}, &1))

  test "the row, its stars, and its files go, and another photo keeps its own", ctx do
    other = activity_photo_fixture(ctx.activity, %{status: :accepted})
    user = user_fixture()

    for photo <- [ctx.photo, other],
        person <- [user, user_fixture()],
        do: {:ok, true} = StarActivityPhoto.call(photo, person)

    assert DeleteActivityPhoto.call(ctx.team, ctx.photo) == :ok

    assert Repo.reload(ctx.photo) == nil
    assert stars(ctx.photo) == 0
    assert files_gone?(ctx.photo)

    assert Repo.reload(other)
    assert stars(other) == 2
    assert files_kept?(other)
  end

  test "a waiting photo goes the same way", ctx do
    waiting = activity_photo_fixture(ctx.activity)

    assert DeleteActivityPhoto.call(ctx.team, waiting) == :ok
    assert Repo.reload(waiting) == nil
    assert files_gone?(waiting)
  end

  test "another team's photo is never touched", ctx do
    other_team = team_fixture(%{photos_enabled: true})
    {:ok, true} = StarActivityPhoto.call(ctx.photo, user_fixture())

    assert DeleteActivityPhoto.call(other_team, ctx.photo) == :ok

    assert Repo.reload(ctx.photo)
    assert stars(ctx.photo) == 1
    assert files_kept?(ctx.photo)
  end

  test "one that is gone already is done", ctx do
    assert DeleteActivityPhoto.call(ctx.team, ctx.photo) == :ok
    assert DeleteActivityPhoto.call(ctx.team, ctx.photo) == :ok
  end
end

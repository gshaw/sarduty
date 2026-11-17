defmodule App.Operation.StarActivityPhotoTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.ActivityPhoto
  alias App.Model.ActivityPhotoStar
  alias App.Operation.StarActivityPhoto

  # Stars on an accepted activity photo (#1033): one each, and a second takes it back.
  setup do
    team = team_fixture(%{photos_enabled: true})
    activity = activity_fixture(team)

    %{
      photo: activity_photo_fixture(activity, %{status: :accepted}),
      waiting: activity_photo_fixture(activity),
      user: user_fixture(),
      other: user_fixture()
    }
  end

  defp stars(photo, user), do: [photo] |> ActivityPhoto.put_stars(user) |> hd()

  test "a star counts once for each person, and starring again removes it", ctx do
    assert StarActivityPhoto.call(ctx.photo, ctx.user) == {:ok, true}
    assert %{stars: 1, starred: true} = stars(ctx.photo, ctx.user)

    assert StarActivityPhoto.call(ctx.photo, ctx.other) == {:ok, true}
    assert %{stars: 2, starred: true} = stars(ctx.photo, ctx.user)

    assert StarActivityPhoto.call(ctx.photo, ctx.user) == {:ok, false}
    assert %{stars: 1, starred: false} = stars(ctx.photo, ctx.user)
    assert %{stars: 1, starred: true} = stars(ctx.photo, ctx.other)

    assert StarActivityPhoto.call(ctx.photo, ctx.user) == {:ok, true}
    assert %{stars: 2} = stars(ctx.photo, ctx.user)
  end

  test "one person never holds two stars on a photo", ctx do
    {:ok, true} = StarActivityPhoto.call(ctx.photo, ctx.user)

    # A second tab that starred it first: the table refuses a second row.
    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%ActivityPhotoStar{
        team_id: ctx.photo.team_id,
        activity_photo_id: ctx.photo.id,
        user_id: ctx.user.id
      })
    end
  end

  test "a waiting photo takes no star", ctx do
    assert StarActivityPhoto.call(ctx.waiting, ctx.user) == {:error, :waiting}
    assert %{stars: 0, starred: false} = stars(ctx.waiting, ctx.user)
  end

  test "a star on one photo leaves the others alone", ctx do
    second = activity_photo_fixture(activity_fixture(team_fixture()), %{status: :accepted})
    {:ok, true} = StarActivityPhoto.call(ctx.photo, ctx.user)

    assert [%{stars: 1, starred: true}, %{stars: 0, starred: false}] =
             ActivityPhoto.put_stars([ctx.photo, second], ctx.user)
  end
end

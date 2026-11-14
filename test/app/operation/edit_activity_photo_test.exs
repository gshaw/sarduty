defmodule App.Operation.EditActivityPhotoTest do
  # Not async: Clean up's mode is the app's config.
  use App.DataCase

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Adapter.FileStore
  alias App.CleanUpStandIn
  alias App.Model.ActivityPhoto
  alias App.Operation.EditActivityPhoto

  # Edit photo (#1032, part 8): the settings go on the row, the copies are made again
  # from the original, and the original never changes.
  setup do
    team = team_fixture(%{photos_enabled: true})
    activity = activity_fixture(team)
    photo = activity_photo_fixture(activity, %{status: :accepted})
    %{team: team, photo: photo, user: user_fixture()}
  end

  @now ~U[2026-11-12 18:00:00.000000Z]

  defp files(photo),
    do: Map.new(ActivityPhoto.sizes(), &{&1, photo |> ActivityPhoto.key(&1) |> file()})

  defp file(key) do
    {:ok, bytes} = FileStore.get(key)
    bytes
  end

  defp size(bytes) do
    image = Image.from_binary!(bytes)
    {Image.width(image), Image.height(image)}
  end

  test "saving keeps the original's bytes and makes the copies from it again", ctx do
    before = files(ctx.photo)
    settings = %{turns: 1, angle: 2.5, clean_up: false}

    assert {:ok, saved} = EditActivityPhoto.call(ctx.team, ctx.photo, settings, ctx.user, @now)

    assert {saved.turns, saved.angle, saved.clean_up} == {1, 2.5, false}
    assert saved.edited_by_user_id == ctx.user.id
    assert saved.edited_at == @now
    assert DateTime.compare(saved.updated_at, ctx.photo.updated_at) == :gt

    now = files(saved)
    assert now.original == before.original
    assert now.show != before.show and now.tile != before.tile
    # The 60 × 40 photo, turned a quarter and cut a little for the angle.
    {width, height} = size(now.show)
    assert width < height and height <= 60
  end

  test "Revert to original clears the edit and brings the copies back", ctx do
    before = files(ctx.photo)

    {:ok, saved} =
      EditActivityPhoto.call(
        ctx.team,
        ctx.photo,
        %{turns: 2, angle: -4, clean_up: false},
        ctx.user,
        @now
      )

    assert {:ok, reverted} = EditActivityPhoto.revert(ctx.team, saved, @now)

    assert {reverted.turns, reverted.angle, reverted.clean_up} == {0, 0.0, false}
    assert reverted.edited_at == nil and reverted.edited_by_user_id == nil
    now = files(reverted)
    assert now.original == before.original
    assert size(now.show) == size(before.show)
    assert size(now.tile) == size(before.tile)
  end

  test "saving no change is no edit", ctx do
    assert {:ok, saved} =
             EditActivityPhoto.call(
               ctx.team,
               ctx.photo,
               %{turns: 4, angle: 0, clean_up: false},
               ctx.user,
               @now
             )

    assert saved.turns == 0
    assert saved.edited_at == nil
  end

  test "a waiting photo is not edited", ctx do
    waiting = activity_photo_fixture(activity_fixture(ctx.team))
    before = files(waiting)

    assert EditActivityPhoto.call(
             ctx.team,
             waiting,
             %{turns: 1, angle: 0, clean_up: false},
             ctx.user,
             @now
           ) ==
             {:error, :waiting}

    assert files(waiting) == before
    assert Repo.reload(waiting).turns == 0
  end

  test "another team's photo is not edited through this team", ctx do
    other = team_fixture(%{photos_enabled: true})

    assert EditActivityPhoto.call(
             other,
             ctx.photo,
             %{turns: 1, angle: 0, clean_up: false},
             ctx.user,
             @now
           ) ==
             {:error, :gone}

    assert Repo.reload(ctx.photo).turns == 0
  end

  test "check/1 takes accepted photos only" do
    assert EditActivityPhoto.check(%ActivityPhoto{status: :accepted}) == :ok
    assert EditActivityPhoto.check(%ActivityPhoto{status: :waiting}) == {:error, :waiting}
  end

  describe "Clean up" do
    test "off, it is not run and the photo saves without it", ctx do
      refute EditActivityPhoto.clean_up_available?()

      assert {:ok, saved} =
               EditActivityPhoto.call(
                 ctx.team,
                 ctx.photo,
                 %{turns: 0, angle: 0, clean_up: true},
                 ctx.user,
                 @now
               )

      refute saved.clean_up
      assert saved.edited_at == nil
    end

    test "on, the copies are its answer", ctx do
      white = 60 |> Image.new!(40, color: :white) |> Image.write!(:memory, suffix: ".jpg")

      CleanUpStandIn.turn_on(
        answer: fn _jpeg, :activity -> {:ok, %{bytes: white, faces: nil, face: nil}} end
      )

      assert {:ok, saved} =
               EditActivityPhoto.call(
                 ctx.team,
                 ctx.photo,
                 %{turns: 0, angle: 0, clean_up: true},
                 ctx.user,
                 @now
               )

      assert saved.clean_up
      assert saved.edited_at == @now

      [red, _green, _blue] =
        saved |> files() |> Map.fetch!(:show) |> Image.from_binary!() |> Image.average!()

      assert red > 250
    end

    test "when it fails, the photo saves without it", ctx do
      CleanUpStandIn.turn_on(answer: fn _jpeg, :activity -> {:error, :no_function} end)

      assert {:ok, saved} =
               EditActivityPhoto.call(
                 ctx.team,
                 ctx.photo,
                 %{turns: 1, angle: 0, clean_up: true},
                 ctx.user,
                 @now
               )

      refute saved.clean_up
      assert saved.turns == 1
    end

    test "the preview is the original, cleaned up", ctx do
      CleanUpStandIn.turn_on()
      assert {:ok, jpeg} = EditActivityPhoto.preview(ctx.photo)
      assert size(jpeg) == {60, 40}
    end
  end
end

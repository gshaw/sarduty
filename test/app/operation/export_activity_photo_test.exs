defmodule App.Operation.ExportActivityPhotoTest do
  # Not async: Clean up's mode is the app's config.
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.FileStore
  alias App.CleanUpStandIn
  alias App.Model.ActivityPhoto
  alias App.Operation.EditActivityPhoto
  alias App.Operation.ExportActivityPhoto
  alias App.Repo

  # Export for a post (#1032, part 9): a copy of an accepted photo the team may post, in
  # the shape a post needs, from the photo as edited. Nothing is saved.
  setup do
    team = team_fixture(%{photos_enabled: true})
    activity = activity_fixture(team)

    photo =
      activity_photo_fixture(activity, %{
        status: :accepted,
        may_post: true,
        bytes: located_jpeg_fixture(2400, 1600)
      })

    %{team: team, activity: activity, photo: photo}
  end

  @whole %{x: 0.5, y: 0.5, side: 1.0}

  defp size(jpeg) do
    image = Image.from_binary!(jpeg)
    {Image.width(image), Image.height(image)}
  end

  defp files(photo), do: for({_size, key} <- ActivityPhoto.keys(photo), do: FileStore.get(key))

  test "check/1: accepted photos the team may post only" do
    assert ExportActivityPhoto.check(%ActivityPhoto{status: :accepted, may_post: true}) == :ok

    assert ExportActivityPhoto.check(%ActivityPhoto{status: :accepted, may_post: false}) ==
             {:error, :may_not_post}

    assert ExportActivityPhoto.check(%ActivityPhoto{status: :waiting, may_post: true}) ==
             {:error, :waiting}
  end

  test "the download is a JPEG of the shape's size, with no location data", ctx do
    assert {:ok, jpeg} = ExportActivityPhoto.call(ctx.team, ctx.photo.id, "portrait", @whole)

    assert Service.Image.kind(jpeg) == :image
    assert <<0xFF, 0xD8, _rest::binary>> = jpeg
    assert size(jpeg) == {1080, 1350}
    assert {:error, _none} = jpeg |> Image.from_binary!() |> Image.exif()
    refute jpeg =~ "Canon"
  end

  test "an original too small for the shape downloads smaller, at the same shape", ctx do
    assert {:ok, jpeg} = ExportActivityPhoto.call(ctx.team, ctx.photo.id, "story", @whole)
    assert size(jpeg) == {900, 1600}

    assert {:ok, jpeg} = ExportActivityPhoto.call(ctx.team, ctx.photo.id, "original", @whole)
    assert size(jpeg) == {2400, 1600}
  end

  test "starts from the photo as edited: turned, at its full size", ctx do
    {:ok, _edited} =
      EditActivityPhoto.call(
        ctx.team,
        ctx.photo,
        %{turns: 1, angle: 0, clean_up: false},
        nil,
        DateTime.utc_now()
      )

    assert {:ok, jpeg} = ExportActivityPhoto.call(ctx.team, ctx.photo.id, "original", @whole)
    assert size(jpeg) == {1600, 2400}
    assert ctx.photo |> Repo.reload() |> ExportActivityPhoto.size() == {1600, 2400}
  end

  test "a cleaned-up photo starts from the cleaned-up copy to show", ctx do
    CleanUpStandIn.turn_on()

    {:ok, edited} =
      EditActivityPhoto.call(
        ctx.team,
        ctx.photo,
        %{turns: 0, angle: 0, clean_up: true},
        nil,
        DateTime.utc_now()
      )

    assert edited.clean_up
    assert ExportActivityPhoto.size(edited) == {2048, 1365}
    assert {:ok, jpeg} = ExportActivityPhoto.call(ctx.team, ctx.photo.id, "original", @whole)
    assert size(jpeg) == {2048, 1365}
  end

  test "nothing is saved by an export", ctx do
    before = files(ctx.photo)
    assert {:ok, _jpeg} = ExportActivityPhoto.call(ctx.team, ctx.photo.id, "square", @whole)

    assert Repo.reload(ctx.photo) == ctx.photo
    assert files(ctx.photo) == before
  end

  test "a photo the team may not post, and a waiting one, are refused", ctx do
    no = activity_photo_fixture(ctx.activity, %{status: :accepted, may_post: false})
    assert ExportActivityPhoto.call(ctx.team, no.id, "square", @whole) == {:error, :may_not_post}

    waiting = activity_photo_fixture(ctx.activity, %{may_post: true})

    assert_raise Ecto.NoResultsError, fn ->
      ExportActivityPhoto.call(ctx.team, waiting.id, "square", @whole)
    end
  end

  test "scoped to the team", ctx do
    other = team_fixture(%{photos_enabled: true})

    assert_raise Ecto.NoResultsError, fn ->
      ExportActivityPhoto.call(other, ctx.photo.id, "square", @whole)
    end
  end
end

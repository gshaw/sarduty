defmodule Service.ActivityPhotoTest do
  use ExUnit.Case, async: true

  import App.DataFixtures, only: [png_fixture: 2, located_jpeg_fixture: 2]

  alias Service.ActivityPhoto

  # A photo on its way to an activity (#1032): what is kept of it, and what is not.
  defp size(bytes) do
    image = Image.from_binary!(bytes)
    {Image.width(image), Image.height(image)}
  end

  defp jpeg?(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: true
  defp jpeg?(_bytes), do: false

  describe "prepare/1" do
    test "keeps the original at its full size, a copy to show, and one for tiles" do
      assert {:ok, files} = 3000 |> png_fixture(2000) |> ActivityPhoto.prepare()

      assert {files.width, files.height} == {3000, 2000}
      assert size(files.original) == {3000, 2000}
      assert size(files.show) == {2048, 1365}
      assert size(files.tile) == {600, 400}
      assert Enum.all?([files.original, files.show, files.tile], &jpeg?/1)
    end

    test "a small photo is never enlarged" do
      assert {:ok, files} = 400 |> png_fixture(300) |> ActivityPhoto.prepare()

      for bytes <- [files.original, files.show, files.tile],
          do: assert(size(bytes) == {400, 300})
    end

    test "strips where a photo was taken and with what, from every file" do
      located = located_jpeg_fixture(800, 600)

      # The photo as the phone sent it does say where.
      assert {:ok, %{gps: gps, make: "Canon"}} = located |> Image.from_binary!() |> Image.exif()
      assert gps != %{}
      assert located =~ "Exif"

      assert {:ok, files} = ActivityPhoto.prepare(located)

      for bytes <- [files.original, files.show, files.tile] do
        refute bytes =~ "Exif"
        refute bytes =~ "Canon"
        assert {:error, _no_exif} = bytes |> Image.from_binary!() |> Image.exif()
      end
    end

    test "says what to do with a file that is not a photo, or one too large" do
      assert ActivityPhoto.prepare("%PDF-1.7 a document") ==
               {:error, "Select photos. SAR Duty cannot read this file."}

      # A JPEG's first bytes, and nothing a photo has after them.
      assert ActivityPhoto.prepare(<<0xFF, 0xD8, 0xFF, 0xE0, "not a photo">>) ==
               {:error, "SAR Duty cannot read this photo. Select another."}

      too_large = <<0xFF, 0xD8, 0xFF>> <> :binary.copy(<<0>>, ActivityPhoto.max_bytes())
      assert ActivityPhoto.prepare(too_large) == {:error, "Select photos under 25 MB each."}
    end
  end

  describe "check/1" do
    test "a photo passes, from its header" do
      assert 800 |> png_fixture(600) |> ActivityPhoto.check() == :ok
      assert 800 |> located_jpeg_fixture(600) |> ActivityPhoto.check() == :ok
    end

    test "says what to do with a file SAR Duty cannot read" do
      assert ActivityPhoto.check("%PDF-1.7 a document") ==
               {:error, "Select photos. SAR Duty cannot read this file."}

      # A HEIC file's first bytes, with no photo after them.
      # cspell:ignore ftypheic -- the HEIF box type "ftyp" and its brand "heic", run together
      heic = <<0, 0, 0, 24, "ftypheic", 0, 0, 0, 0, "not a photo">>

      assert ActivityPhoto.check(heic) ==
               {:error, "SAR Duty cannot read this photo. Select a JPEG."}
    end
  end

  test "the limits Add photos shows" do
    assert ActivityPhoto.max_photos() == 20
    assert ActivityPhoto.max_bytes() == 25_000_000
    assert ActivityPhoto.max_caption() == 300
  end

  # Edit photo (part 8): settings into what is done to the original.
  describe "plan/2" do
    defp plan(size, turns, angle, clean_up \\ false),
      do: ActivityPhoto.plan(%{turns: turns, angle: angle, clean_up: clean_up}, size)

    test "no edit is nothing to do" do
      assert plan({3000, 2000}, 0, 0) == []
      assert plan({3000, 2000}, 4, 0.1) == []
    end

    test "turns, then the angle with its cut, then Clean up" do
      assert [{:turn, 1}, {:straighten, 5.0, {width, height}}, :clean_up] =
               plan({3000, 2000}, 1, 5, true)

      # Turned, the photo is 2000 × 3000, and the cut keeps that shape.
      assert {width, height} == {1774, 2662}
      assert_in_delta width / height, 2000 / 3000, 0.001
    end

    test "left is three turns right" do
      assert plan({3000, 2000}, -1, 0) == [{:turn, 3}]
    end

    test "the angle is kept to 10° either way, in steps of 0.5°" do
      assert [{:straighten, 10.0, _cut}] = plan({300, 200}, 0, 14)
      assert [{:straighten, -10.0, _cut}] = plan({300, 200}, 0, -30)
      assert [{:straighten, 2.5, _cut}] = plan({300, 200}, 0, 2.4)
      assert [{:straighten, -0.5, _cut}] = plan({300, 200}, 0, -0.6)
    end

    test "Clean up alone is the one step" do
      assert plan({300, 200}, 0, 0, true) == [:clean_up]
    end
  end

  describe "cut_scale/2" do
    test "is all of the photo with no angle" do
      assert ActivityPhoto.cut_scale(0, {3000, 2000}) == 1.0
    end

    test "leaves no empty corner: each corner of the cut is inside the turned photo" do
      for {width, height} <- [{3000, 2000}, {2000, 3000}, {1000, 1000}],
          angle <- [-10, -3.5, 0.5, 10] do
        scale = ActivityPhoto.cut_scale(angle, {width, height})
        radians = angle * :math.pi() / 180
        {cos, sin} = {:math.cos(radians), :math.sin(radians)}

        for x <- [-1, 1], y <- [-1, 1] do
          {cx, cy} = {x * width * scale / 2, y * height * scale / 2}
          # The corner, in the photo's own frame once it is turned back.
          assert abs(cx * cos + cy * sin) <= width / 2 + 0.001
          assert abs(-cx * sin + cy * cos) <= height / 2 + 0.001
        end

        # Just enough: one corner touches an edge.
        assert scale > 0.8 and scale < 1
      end
    end

    test "is the same either way" do
      assert ActivityPhoto.cut_scale(-4, {3000, 2000}) == ActivityPhoto.cut_scale(4, {3000, 2000})
    end
  end

  describe "edit/3" do
    defp no_clean_up(_jpeg), do: flunk("Clean up ran")

    test "turns the photo and makes both copies from it" do
      original = 3000 |> png_fixture(2000) |> Service.Image.full_jpeg() |> elem(1)
      steps = ActivityPhoto.plan(%{turns: 1, angle: 0, clean_up: false}, {3000, 2000})

      assert {:ok, %{show: show, tile: tile, cleaned?: false}} =
               ActivityPhoto.edit(original, steps, &no_clean_up/1)

      assert size(show) == {1365, 2048}
      assert size(tile) == {400, 600}
    end

    test "straightens with a cut at the photo's shape, with no empty corner" do
      # Red all over: an empty corner would be black.
      original =
        1200 |> Image.new!(800, color: :red) |> Image.write!(:memory, suffix: ".jpg")

      steps = ActivityPhoto.plan(%{turns: 0, angle: 10, clean_up: false}, {1200, 800})
      assert {:ok, %{show: show}} = ActivityPhoto.edit(original, steps, &no_clean_up/1)

      {width, height} = size(show)
      assert_in_delta width / height, 1.5, 0.01
      image = Image.from_binary!(show)

      for {x, y} <- [{0, 0}, {width - 1, 0}, {0, height - 1}, {width - 1, height - 1}] do
        [red, _green, _blue] = Image.get_pixel!(image, x, y)
        assert red > 200
      end
    end

    test "Clean up gets the copy to show, and both copies come from its answer" do
      original = 800 |> png_fixture(600) |> Service.Image.full_jpeg() |> elem(1)
      white = 800 |> Image.new!(600, color: :white) |> Image.write!(:memory, suffix: ".jpg")

      clean_up = fn jpeg ->
        assert size(jpeg) == {800, 600}
        {:ok, white}
      end

      assert {:ok, %{show: show, tile: tile, cleaned?: true}} =
               ActivityPhoto.edit(original, [:clean_up], clean_up)

      for bytes <- [show, tile] do
        assert [red, _green, _blue] = bytes |> Image.from_binary!() |> Image.average!()
        assert red > 250
      end
    end

    test "when Clean up does not answer, the copies are made without it" do
      original = 800 |> png_fixture(600) |> Service.Image.full_jpeg() |> elem(1)

      assert {:ok, %{show: show, cleaned?: false}} =
               ActivityPhoto.edit(original, [:clean_up], fn _jpeg -> {:error, :timeout} end)

      assert size(show) == {800, 600}
    end
  end
end

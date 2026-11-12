defmodule Service.PhotoExportTest do
  use ExUnit.Case, async: true

  alias Service.PhotoExport

  # Export for a post (#1032, part 9): the shape, the box, and the photo's size in; the
  # crop and the size it downloads at out.
  @whole %{x: 0.5, y: 0.5, side: 1.0}
  @phone {4032, 3024}

  defp shape(key), do: PhotoExport.shape(key)

  test "the shapes, with the size each downloads at and where it is used" do
    assert for(s <- PhotoExport.shapes(), do: {s.label, s.size, s.used_for}) == [
             {"Square 1:1", {1080, 1080}, "Instagram, Facebook"},
             {"Portrait 4:5", {1080, 1350}, "Instagram feed"},
             {"Landscape 16:9", {1920, 1080}, "Facebook, website, YouTube"},
             {"Story 9:16", {1080, 1920}, "Instagram and Facebook stories"},
             {"Original", nil, "Anywhere"}
           ]

    assert shape("nope").key == "square"
    assert shape(nil).key == "square"
  end

  describe "crop/3, zoomed all the way out" do
    test "a square is the middle of a wide photo, at 1080 × 1080" do
      assert PhotoExport.crop(shape("square"), @whole, @phone) ==
               %{left: 504, top: 0, width: 3024, height: 3024, out_width: 1080, out_height: 1080}
    end

    test "a portrait is the photo's full height, at 1080 × 1350" do
      assert PhotoExport.crop(shape("portrait"), @whole, @phone) ==
               %{left: 807, top: 0, width: 2419, height: 3024, out_width: 1080, out_height: 1350}
    end

    test "a landscape is the photo's full width, at 1920 × 1080" do
      assert PhotoExport.crop(shape("landscape"), @whole, @phone) ==
               %{left: 0, top: 378, width: 4032, height: 2268, out_width: 1920, out_height: 1080}
    end

    test "a story from a tall photo, at 1080 × 1920" do
      assert PhotoExport.crop(shape("story"), @whole, {3024, 4032}) ==
               %{left: 378, top: 0, width: 2268, height: 4032, out_width: 1080, out_height: 1920}
    end

    test "Original is the whole photo at its own size" do
      assert PhotoExport.crop(shape("original"), @whole, @phone) ==
               %{left: 0, top: 0, width: 4032, height: 3024, out_width: 4032, out_height: 3024}
    end
  end

  describe "crop/3, placed" do
    test "zoomed in to half, in the top left corner" do
      assert PhotoExport.crop(shape("square"), %{x: 0.0, y: 0.0, side: 0.5}, @phone) ==
               %{left: 0, top: 0, width: 1512, height: 1512, out_width: 1080, out_height: 1080}
    end

    test "a centre past the edge keeps the box inside" do
      crop = PhotoExport.crop(shape("portrait"), %{x: 1.4, y: -2.0, side: 0.5}, @phone)
      assert {crop.left + crop.width, crop.top} == {4032, 0}
    end

    test "never under a fifth of the largest box, whatever was sent" do
      crop = PhotoExport.crop(shape("square"), %{x: 0.5, y: 0.5, side: 0.01}, @phone)
      assert {crop.width, crop.height} == {605, 605}
    end

    test "Original zoomed in downloads at the box's size" do
      crop = PhotoExport.crop(shape("original"), %{x: 0.5, y: 0.5, side: 0.5}, @phone)

      assert {crop.width, crop.height, crop.out_width, crop.out_height} ==
               {2016, 1512, 2016, 1512}
    end
  end

  describe "crop/3, an original too small for the shape" do
    test "downloads at the box's size, at the same shape, never enlarged" do
      assert PhotoExport.crop(shape("landscape"), @whole, {1200, 900}) ==
               %{left: 0, top: 113, width: 1200, height: 675, out_width: 1200, out_height: 675}
    end

    test "a story from a small wide photo" do
      crop = PhotoExport.crop(shape("story"), @whole, {800, 600})
      assert {crop.out_width, crop.out_height} == {338, 600}
      assert {crop.width, crop.height} == {338, 600}
    end

    test "a zoomed-in box on a big photo can be too small too" do
      crop = PhotoExport.crop(shape("square"), %{x: 0.5, y: 0.5, side: 0.25}, {2000, 1500})
      assert {crop.width, crop.out_width, crop.out_height} == {375, 375, 375}
    end
  end

  test "ratio/2 is the shape's, or the photo's for Original" do
    assert PhotoExport.ratio(shape("portrait"), @phone) == 0.8
    assert PhotoExport.ratio(shape("original"), {60, 40}) == 1.5
  end

  test "export/3 cuts the photo out at the size to download, with no metadata" do
    image = Image.new!(4032, 3024, color: :steelblue)
    {:ok, jpeg} = PhotoExport.export(image, shape("portrait"), @whole)
    {:ok, out} = Image.from_binary(jpeg)

    assert {Image.width(out), Image.height(out)} == {1080, 1350}
    assert {:error, _none} = Image.exif(out)
  end
end

defmodule Service.ImageTest do
  use ExUnit.Case, async: true

  import App.DataFixtures, only: [png_fixture: 2]

  # The PNG signature, so a JPEG passed through unchanged would fail.
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  defp size({:ok, png}) do
    assert binary_part(png, 0, 8) == @png_signature
    image = Image.from_binary!(png)
    {Image.width(image), Image.height(image)}
  end

  test "crops a photo to a square at its shorter side" do
    for {width, height, side} <- [{640, 480, 480}, {300, 400, 300}, {200, 200, 200}] do
      photo = png_fixture(width, height)
      assert size(Service.Image.square(photo)) == {side, side}
    end
  end

  test "a big photo is scaled down to the limit" do
    photo = png_fixture(1600, 1200)
    assert size(Service.Image.square(photo, 660)) == {660, 660}
  end

  test "pads a tall or wide logo to a square instead of cutting it" do
    tall = png_fixture(1500, 1740)
    wide = png_fixture(800, 504)
    assert size(Service.Image.pad_square(tall, 660)) == {660, 660}
    assert size(Service.Image.pad_square(wide, 180, margin: 0.1)) == {180, 180}
  end

  test "turns a JPEG into a PNG" do
    jpeg = 100 |> Image.new!(50) |> Image.write!(:memory, suffix: ".jpg")
    assert size(Service.Image.png(jpeg, 480)) == {100, 50}
  end

  test "centers the photo in a wide banner" do
    photo = png_fixture(640, 480)
    assert size(Service.Image.banner(photo, 1032, 336, "#1c2d42")) == {1032, 336}
  end

  test "says so when the bytes aren't an image" do
    assert {:error, _} = Service.Image.square("not an image")
  end
end

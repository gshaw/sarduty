defmodule Service.MemberPhotoTest do
  use ExUnit.Case, async: true

  alias Service.MemberPhoto

  # A photo's size, the quarter turns, and the placed square in; the crop out (#1028).
  describe "crop/3" do
    test "the middle square, unturned, is the largest square" do
      assert MemberPhoto.crop({1600, 1200}, 0, %{x: 0.5, y: 0.5, side: 1.0}) ==
               %{turns: 0, left: 200, top: 0, side: 1200}

      assert MemberPhoto.crop({1200, 1600}, 0, %{x: 0.5, y: 0.5, side: 1.0}) ==
               %{turns: 0, left: 0, top: 200, side: 1200}
    end

    test "the square's centre and side are shares of the photo" do
      # Half the shorter side, centred a quarter of the way across and 40% down.
      assert MemberPhoto.crop({2000, 1000}, 0, %{x: 0.25, y: 0.4, side: 0.5}) ==
               %{turns: 0, left: 250, top: 150, side: 500}
    end

    test "a quarter turn swaps the width and the height the shares are of" do
      # 2000 × 1000 turned once is 1000 × 2000: the square's centre is 40% down that.
      assert MemberPhoto.crop({2000, 1000}, 1, %{x: 0.5, y: 0.4, side: 1.0}) ==
               %{turns: 1, left: 0, top: 300, side: 1000}

      assert MemberPhoto.crop({2000, 1000}, 2, %{x: 0.25, y: 0.5, side: 1.0}) ==
               %{turns: 2, left: 0, top: 0, side: 1000}

      assert %{turns: 3, left: 0, top: 300} =
               MemberPhoto.crop({2000, 1000}, 3, %{x: 0.5, y: 0.4, side: 1.0})
    end

    test "turns wrap, either way" do
      placed = %{x: 0.5, y: 0.5, side: 1.0}
      assert MemberPhoto.crop({800, 600}, 4, placed).turns == 0
      assert MemberPhoto.crop({800, 600}, 5, placed) == MemberPhoto.crop({800, 600}, 1, placed)
      assert MemberPhoto.crop({800, 600}, -1, placed).turns == 3
    end

    test "the square stays inside the photo, whatever was sent" do
      assert MemberPhoto.crop({1000, 1000}, 0, %{x: 0.0, y: 1.0, side: 0.5}) ==
               %{turns: 0, left: 0, top: 500, side: 500}

      assert MemberPhoto.crop({1000, 800}, 0, %{x: 7.0, y: -3.0, side: 0.5}) ==
               %{turns: 0, left: 600, top: 0, side: 400}
    end

    test "the zoom stops at a fifth of the shorter side, and at the whole of it" do
      assert MemberPhoto.crop({1000, 800}, 0, %{x: 0.5, y: 0.5, side: 0.01}).side == 160
      assert MemberPhoto.crop({1000, 800}, 0, %{x: 0.5, y: 0.5, side: 9.0}).side == 800
      assert MemberPhoto.crop({3, 2}, 0, %{x: 0.5, y: 0.5, side: 0.2}).side == 1
    end
  end

  describe "placement/1" do
    test "reads the form's hidden fields" do
      params = %{"turns" => "3", "x" => "0.25", "y" => "0.4", "side" => "0.5"}
      assert MemberPhoto.placement(params) == {3, %{x: 0.25, y: 0.4, side: 0.5}}
    end

    test "a field that is missing or not a number takes the middle square, unturned" do
      assert MemberPhoto.placement(%{}) == {0, %{x: 0.5, y: 0.5, side: 1.0}}

      assert MemberPhoto.placement(%{"turns" => "x", "x" => "", "y" => "NaN", "side" => "1e"}) ==
               {0, %{x: 0.5, y: 0.5, side: 1.0}}
    end
  end

  defp image(width, height, format \\ ".png"),
    do: width |> Image.new!(height, color: :steelblue) |> Image.write!(:memory, suffix: format)

  defp size(bytes) do
    image = Image.from_binary!(bytes)
    {Image.width(image), Image.height(image)}
  end

  describe "prepare/1" do
    test "a photo becomes a JPEG up to 2000 px, with its size" do
      assert {:ok, %{bytes: <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg, width: 2000, height: 1500}} =
               MemberPhoto.prepare(image(2400, 1800))

      assert size(jpeg) == {2000, 1500}
    end

    test "a file that is not a photo, or is over 10 MB, says what to do" do
      assert MemberPhoto.prepare("%PDF-1.7") ==
               {:error, "Select a photo. SAR Duty cannot read this file."}

      assert MemberPhoto.prepare(<<0xFF, 0xD8, 0xFF, "not a real photo">>) ==
               {:error, "SAR Duty cannot read this photo. Take another, or select one."}

      assert MemberPhoto.prepare(:binary.copy(<<0>>, 10_000_001)) ==
               {:error, "Select a photo under 10 MB."}
    end
  end

  describe "place/3" do
    test "cuts the placed square and shrinks it to 1024 px, as a JPEG" do
      {:ok, photo} = MemberPhoto.prepare(image(2000, 1500))

      assert {:ok, <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg} =
               MemberPhoto.place(photo.bytes, 0, %{x: 0.5, y: 0.5, side: 1.0})

      assert size(jpeg) == {1024, 1024}
    end

    test "a square under 1024 px keeps its size, turned or not" do
      {:ok, photo} = MemberPhoto.prepare(image(900, 600))

      for turns <- 0..3 do
        {:ok, jpeg} = MemberPhoto.place(photo.bytes, turns, %{x: 0.5, y: 0.5, side: 0.5})
        assert size(jpeg) == {300, 300}
      end
    end

    # Left half red, right half blue: a quarter turn clockwise puts the red on top.
    test "turns the photo clockwise before it cuts" do
      red = Image.new!(400, 800, color: :red)
      blue = Image.new!(400, 800, color: :blue)
      {:ok, joined} = Image.join([red, blue], across: 2)
      {:ok, photo} = MemberPhoto.prepare(Image.write!(joined, :memory, suffix: ".png"))

      {:ok, top} = MemberPhoto.place(photo.bytes, 1, %{x: 0.5, y: 0.0, side: 0.5})
      {:ok, bottom} = MemberPhoto.place(photo.bytes, 1, %{x: 0.5, y: 1.0, side: 0.5})

      assert [r, _g, b] = top |> Image.from_binary!() |> Image.get_pixel!(200, 100)
      assert r > 200 and b < 60
      assert [r, _g, b] = bottom |> Image.from_binary!() |> Image.get_pixel!(200, 300)
      assert r < 60 and b > 200
    end
  end
end

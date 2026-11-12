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

  describe "normalize/1" do
    test "keeps a placement that is in range" do
      placed = {3, %{x: 0.25, y: 0.4, side: 0.5}}
      assert MemberPhoto.normalize(placed) == placed
    end

    test "wraps the turns and pulls the square into range" do
      assert MemberPhoto.normalize({5, %{x: 7.0, y: -3.0, side: 0.01}}) ==
               {1, %{x: 1.0, y: 0.0, side: 0.2}}

      assert MemberPhoto.normalize({-1, %{x: 0.5, y: 0.5, side: 9.0}}) ==
               {3, %{x: 0.5, y: 0.5, side: 1.0}}
    end
  end

  defp image(width, height, format \\ ".png"),
    do: width |> Image.new!(height, color: :steelblue) |> Image.write!(:memory, suffix: format)

  defp size(bytes) do
    image = Image.from_binary!(bytes)
    {Image.width(image), Image.height(image)}
  end

  describe "prepare/1" do
    test "a photo becomes a JPEG up to 2048 px, with its size" do
      assert {:ok,
              %{bytes: <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg, width: 2048, height: 1536}} =
               2400 |> image(1800) |> MemberPhoto.prepare()

      assert size(jpeg) == {2048, 1536}
    end

    test "a file that is not a photo, or is over 10 MB, says what to do" do
      assert MemberPhoto.prepare("%PDF-1.7") ==
               {:error, "Select a photo. SAR Duty cannot read this file."}

      assert MemberPhoto.prepare(<<0xFF, 0xD8, 0xFF, "not a real photo">>) ==
               {:error, "SAR Duty cannot read this photo. Take another, or select one."}

      assert <<0>> |> :binary.copy(10_000_001) |> MemberPhoto.prepare() ==
               {:error, "Select a photo under 10 MB."}
    end
  end

  describe "place/3" do
    test "cuts the placed square and shrinks it to 1024 px, as a JPEG" do
      {:ok, photo} = 2000 |> image(1500) |> MemberPhoto.prepare()

      assert {:ok, <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg} =
               MemberPhoto.place(photo.bytes, 0, %{x: 0.5, y: 0.5, side: 1.0})

      assert size(jpeg) == {1024, 1024}
    end

    test "a square under 1024 px keeps its size, turned or not" do
      {:ok, photo} = 900 |> image(600) |> MemberPhoto.prepare()

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
      {:ok, photo} = joined |> Image.write!(:memory, suffix: ".png") |> MemberPhoto.prepare()

      {:ok, top} = MemberPhoto.place(photo.bytes, 1, %{x: 0.5, y: 0.0, side: 0.5})
      {:ok, bottom} = MemberPhoto.place(photo.bytes, 1, %{x: 0.5, y: 1.0, side: 0.5})

      assert [r, _g, b] = top |> Image.from_binary!() |> Image.get_pixel!(200, 100)
      assert r > 200 and b < 60
      assert [r, _g, b] = bottom |> Image.from_binary!() |> Image.get_pixel!(200, 300)
      assert r < 60 and b > 200
    end
  end

  # Where a cleaned-up photo starts (#1031): the square that puts the face in the oval.
  describe "face_placement/2" do
    defp close?({turns, placed}, {x, y, side}) do
      turns == 0 and abs(placed.x - x) < 0.001 and abs(placed.y - y) < 0.001 and
        abs(placed.side - side) < 0.001
    end

    test "no face takes the middle square" do
      assert MemberPhoto.face_placement({800, 600}, nil) == {0, %{x: 0.5, y: 0.5, side: 1.0}}
    end

    test "a face where the oval is, in a square photo, takes the whole square" do
      assert close?(MemberPhoto.face_placement({600, 600}, MemberPhoto.oval()), {0.5, 0.5, 1.0})
    end

    test "a smaller face zooms in until it is as tall as the oval" do
      # 208 px tall in a 1000 px photo: the oval is 52% of the square, so it is 400 px,
      # centred a tenth of that below the face.
      face = %{x: 0.3, y: 0.3, width: 0.1, height: 0.208}
      assert close?(MemberPhoto.face_placement({1000, 1000}, face), {0.3, 0.34, 0.4})
    end

    test "a wide face is fitted by its width" do
      # 210 px wide: the oval is 42% of the square, so it is 500 px.
      face = %{x: 0.5, y: 0.4, width: 0.21, height: 0.1}
      assert close?(MemberPhoto.face_placement({1000, 1000}, face), {0.5, 0.45, 0.5})
    end

    test "the shares are of the photo's own width and height" do
      # 2000 × 1000: a face 260 px tall asks for a 500 px square, half the shorter side.
      face = %{x: 0.25, y: 0.4, width: 0.05, height: 0.26}
      assert close?(MemberPhoto.face_placement({2000, 1000}, face), {0.25, 0.45, 0.5})
    end

    test "the square is never over the photo, or under the closest zoom" do
      huge = %{x: 0.5, y: 0.5, width: 0.9, height: 0.9}
      assert {0, %{side: 1.0}} = MemberPhoto.face_placement({800, 600}, huge)

      tiny = %{x: 0.5, y: 0.5, width: 0.01, height: 0.01}
      assert close?(MemberPhoto.face_placement({1000, 1000}, tiny), {0.5, 0.52, 0.2})
    end
  end

  # A dark photo (#1031): under a fifth of full brightness, over the whole photo.
  describe "dark?/1" do
    defp grey(level) do
      200
      |> Image.new!(200, color: [level, level, level])
      |> Image.write!(:memory, suffix: ".jpg")
    end

    test "a black or nearly black photo is dark" do
      for level <- [0, 40], do: assert(level |> grey() |> MemberPhoto.dark?())
    end

    test "a dim photo over a fifth of full brightness is not" do
      for level <- [64, 128, 255], do: refute(level |> grey() |> MemberPhoto.dark?())
    end

    test "brightness is as the eye finds it: green counts for more than blue" do
      blue = 200 |> Image.new!(200, color: [0, 0, 255]) |> Image.write!(:memory, suffix: ".jpg")
      green = 200 |> Image.new!(200, color: [0, 255, 0]) |> Image.write!(:memory, suffix: ".jpg")

      assert MemberPhoto.dark?(blue)
      refute MemberPhoto.dark?(green)
    end

    test "a dark photo with a bright window in it is not dark for sure" do
      dark = Image.new!(300, 300, color: [20, 20, 20])
      {:ok, joined} = Image.join([dark, Image.new!(300, 300, color: :white)], across: 2)
      refute joined |> Image.write!(:memory, suffix: ".jpg") |> MemberPhoto.dark?()
    end

    test "bytes that are not a photo are not dark" do
      refute MemberPhoto.dark?("not a photo")
    end
  end
end

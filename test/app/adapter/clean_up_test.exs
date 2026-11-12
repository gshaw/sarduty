defmodule App.Adapter.CleanUpTest do
  # Not async: the mode is the app's config.
  use ExUnit.Case

  import App.DataFixtures, only: [png_fixture: 2]

  alias App.Adapter.CleanUp
  alias App.CleanUpStandIn

  # Clean up's adapter (#1031): off unless config says otherwise, and a stand-in for dev
  # and tests until the function exists.
  defp size(bytes) do
    image = Image.from_binary!(bytes)
    {Image.width(image), Image.height(image)}
  end

  test "off by default: not available, and a call does nothing" do
    refute CleanUp.available?()
    assert 800 |> png_fixture(600) |> CleanUp.call(:member) == {:error, :off}
  end

  test "the stand-in cuts a centred square and reports 1 face, where the oval is" do
    CleanUpStandIn.turn_on()
    assert CleanUp.available?()

    # Red, white, red: the middle square of a wide photo is the white.
    red = Image.new!(300, 300, color: :red)
    {:ok, joined} = Image.join([red, Image.new!(300, 300, color: :white), red], across: 3)
    wide = Image.write!(joined, :memory, suffix: ".jpg")

    assert {:ok, %{bytes: cleaned, faces: 1, face: face}} = CleanUp.call(wide, :member)
    assert size(cleaned) == {300, 300}
    assert [red, green, blue] = cleaned |> Image.from_binary!() |> Image.average!()
    assert red > 250 and green > 250 and blue > 250
    assert face == %{x: 0.5, y: 0.4, width: 0.42, height: 0.52}

    assert {:ok, %{bytes: tall}} = 600 |> png_fixture(800) |> CleanUp.call(:member)
    assert size(tall) == {600, 600}
  end

  test "the stand-in says so when it cannot read the photo" do
    CleanUpStandIn.turn_on()
    assert {:error, _reason} = CleanUp.call("not a photo", :member)
  end

  test "it gives up when the answer takes too long" do
    CleanUpStandIn.turn_on(
      timeout: 20,
      answer: fn _jpeg, :member ->
        Process.sleep(5_000)
        CleanUpStandIn.found(1)
      end
    )

    assert 10 |> png_fixture(10) |> CleanUp.call(:member) == {:error, :timeout}
  end

  test "an answer that crashes is an error, not the caller's crash" do
    CleanUpStandIn.turn_on(answer: fn _jpeg, :member -> raise "no function" end)
    assert {:error, %RuntimeError{message: "no function"}} = CleanUp.call("jpeg", :member)
  end

  test "for an activity photo, the stand-in fixes the light and colour, and keeps the shape" do
    CleanUpStandIn.turn_on()

    # A dull photo: greys close together. Fixed, they stretch to dark and light.
    strips = for grey <- 100..145//5, do: Image.new!(40, 100, color: [grey, grey, grey])
    {:ok, joined} = Image.join(strips, across: 10)
    photo = Image.write!(joined, :memory, suffix: ".jpg")

    assert {:ok, %{bytes: cleaned, faces: nil, face: nil}} = CleanUp.call(photo, :activity)
    assert size(cleaned) == {400, 100}
    image = Image.from_binary!(cleaned)
    [left | _rest] = Image.get_pixel!(image, 5, 50)
    [right | _rest] = Image.get_pixel!(image, 395, 50)
    assert left < 60 and right > 200
  end
end

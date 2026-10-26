defmodule App.Model.CoordinateTest do
  use ExUnit.Case, async: true

  alias App.Model.Coordinate

  describe "parse/1" do
    test "decimals, with a comma or a space" do
      assert Coordinate.parse("49.01732, -122.65634") == {49.01732, -122.65634}
      assert Coordinate.parse("49.01732,-122.65634") == {49.01732, -122.65634}
      assert Coordinate.parse(" 45.3653 -63.2797 ") == {45.3653, -63.2797}
    end

    test "hemispheres before or after, and longitude first" do
      assert Coordinate.parse("49.0173 N, 122.6563 W") == {49.0173, -122.6563}
      assert Coordinate.parse("N49.0173 W122.6563") == {49.0173, -122.6563}
      assert Coordinate.parse("122.6563W 49.0173N") == {49.0173, -122.6563}
      assert Coordinate.parse("33.9 S 151.2 E") == {-33.9, 151.2}
    end

    test "degrees, minutes, and seconds as Google copies them" do
      assert Coordinate.parse(~s(49°01'02.4"N 122°39'22.8"W)) == {49.01733, -122.65633}
    end

    test "degrees and minutes, as a GPS shows them" do
      assert Coordinate.parse("N 49° 01.040' W 122° 39.380'") == {49.01733, -122.65633}
      assert Coordinate.parse("49 01.040, -122 39.380") == {49.01733, -122.65633}
    end

    test "a Google or Apple Maps link" do
      assert Coordinate.parse("https://www.google.com/maps/@49.0173,-122.6563,15z") ==
               {49.0173, -122.6563}

      assert Coordinate.parse("https://maps.apple.com/?ll=45.3653,-63.2797&q=Truro") ==
               {45.3653, -63.2797}

      assert Coordinate.parse("https://maps.google.com/?q=49.0173%2C-122.6563") ==
               {49.0173, -122.6563}
    end

    test "an address or a place name is not a coordinate" do
      for text <- [
            "Victoria Park, Truro",
            "20285 8 Ave, Langley",
            "12 34",
            "100 W 4th Ave",
            "North Shore",
            "",
            "https://example.com/"
          ] do
        assert Coordinate.parse(text) == nil, text
      end
    end

    test "out of range, or minutes of 60 or more, is not a coordinate" do
      assert Coordinate.parse("91.0, 10.0") == nil
      assert Coordinate.parse("10.0, 181.0") == nil
      assert Coordinate.parse("49 61.0 N 122 30.0 W") == nil
      assert Coordinate.parse("49.0 N 49.0 N") == nil
    end
  end
end

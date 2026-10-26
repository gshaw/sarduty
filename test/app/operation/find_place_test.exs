defmodule App.Operation.FindPlaceTest do
  use ExUnit.Case, async: true

  alias App.Operation.FindPlace

  test "a place's text is its name and address, without the country" do
    place = %{
      name: "Campbell Valley Regional Park",
      address: "20285 8 Ave, Langley, V2Z 1V5, Canada",
      country: "Canada"
    }

    assert FindPlace.place_text(place) ==
             "Campbell Valley Regional Park, 20285 8 Ave, Langley, V2Z 1V5"
  end

  test "an address says its first line once" do
    place = %{
      name: "20285 8 Ave",
      address: "20285 8 Ave, Langley, V2Z 1V5, Canada",
      country: "Canada"
    }

    assert FindPlace.place_text(place) == "20285 8 Ave, Langley, V2Z 1V5"
  end

  test "a place's text fits D4H's 100 characters" do
    place = %{name: String.duplicate("a", 90), address: "Somewhere Long, Town", country: nil}
    assert place |> FindPlace.place_text() |> String.length() == 100
  end

  defp row(address, coordinate, day),
    do: %{
      address: address,
      coordinate: coordinate,
      started_at: ~U[2026-10-01 18:00:00Z] |> DateTime.add(day, :day)
    }

  describe "rank/1" do
    test "puts the most used place first, then the most recently used" do
      rows = [
        row("Hall", "49.10788,-122.82894", 1),
        row("Hall", "49.10788,-122.82894", 2),
        row("Park", "49.2,-122.9", 3),
        row("Beach", "49.3,-122.7", 4)
      ]

      assert [%{text: "Hall", count: 2}, %{text: "Beach"}, %{text: "Park"}] = FindPlace.rank(rows)
    end

    test "makes pins about 100 m apart one place, with the text used most" do
      rows = [
        row("17499 20 Ave", "49.03861,-122.73800", 1),
        row("17543 20th Ave", "49.03879,-122.73734", 2),
        row("17543 20th Ave", "49.03879,-122.73734", 3)
      ]

      assert [place] = FindPlace.rank(rows)
      assert place.text == "17543 20th Ave"
      assert place.coordinate == "49.03879,-122.73734"
      assert place.count == 3
      assert place.last_at == ~U[2026-10-04 18:00:00Z]
    end

    test "groups places without a pin by their text" do
      rows = [row("Murrin Park", nil, 1), row("murrin park", "0.00000,0.00000", 2)]
      assert [%{count: 2, coordinate: nil}] = FindPlace.rank(rows)
    end
  end

  describe "match_past/2" do
    setup do
      places =
        FindPlace.rank([
          row("Hall, Surrey", "49.1,-122.8", 1),
          row("Hall, Surrey", "49.1,-122.8", 2),
          row("Park, Langley", "49.2,-122.6", 3),
          row("Park, Langley", "49.2,-122.6", 4),
          row("Beach, White Rock", "49.0,-122.8", 5),
          row("Beach, White Rock", "49.0,-122.8", 6),
          row("Pond, Surrey", "49.15,-122.75", 7),
          row("Pond, Surrey", "49.15,-122.75", 8),
          row("Dam, Surrey", "49.3,-122.5", 9)
        ])

      %{places: places}
    end

    test "before typing, the 3 most used that were used more than once", %{places: places} do
      assert places |> FindPlace.match_past("") |> Enum.map(& &1.text) ==
               ["Pond, Surrey", "Beach, White Rock", "Park, Langley"]
    end

    test "after typing, the places that hold every word", %{places: places} do
      assert places |> FindPlace.match_past("surrey h") |> Enum.map(& &1.text) == ["Hall, Surrey"]

      assert places |> FindPlace.match_past("SURREY") |> Enum.map(& &1.text) ==
               ["Pond, Surrey", "Hall, Surrey", "Dam, Surrey"]
    end
  end
end

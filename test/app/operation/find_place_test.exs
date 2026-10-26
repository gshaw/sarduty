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
end

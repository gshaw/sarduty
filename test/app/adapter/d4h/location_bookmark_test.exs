defmodule App.Adapter.D4H.LocationBookmarkTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.LocationBookmark

  test "a bookmark's address is one line and its pin is latitude first" do
    bookmark =
      LocationBookmark.build(%{
        "id" => 7,
        "title" => "!Office",
        "address" => %{
          "street" => "17543 20 Ave",
          "town" => "Surrey",
          "region" => "BC",
          "postcode" => "V3Z 9V1",
          "country" => "Canada"
        },
        "location" => %{"type" => "Point", "coordinates" => [-122.73734, 49.03879]},
        "archivedAt" => nil
      })

    assert bookmark.d4h_location_bookmark_id == 7
    assert bookmark.title == "!Office"
    assert bookmark.address == "17543 20 Ave, Surrey, BC, Canada"
    assert bookmark.coordinate == {49.03879, -122.73734}
    assert bookmark.archived_at == nil
  end

  test "no address and no pin" do
    bookmark =
      LocationBookmark.build(%{
        "id" => 7,
        "title" => "Base",
        "address" => nil,
        "location" => nil,
        "archivedAt" => "2026-10-01T00:00:00.000Z"
      })

    assert {bookmark.address, bookmark.coordinate} == {"", nil}
    assert bookmark.archived_at == ~U[2026-10-01 00:00:00Z]
  end
end

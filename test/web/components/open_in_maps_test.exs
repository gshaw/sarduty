defmodule Web.Components.OpenInMapsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.OpenInMaps

  alias Web.Components.OpenInMaps

  describe "url/4" do
    test "pins the latitude and longitude, with Apple's label" do
      assert OpenInMaps.url("google", "49.6431,-123.2089", "Murrin Park", "Rope practice") ==
               "https://www.google.com/maps/search/?api=1&query=49.6431%2C-123.2089"

      assert OpenInMaps.url("apple", "49.6431,-123.2089", "Murrin Park", "Rope practice") ==
               "https://maps.apple.com/?ll=49.6431%2C-123.2089&q=Rope+practice"
    end

    test "labels Apple's pin with the latitude and longitude when there is no label" do
      assert OpenInMaps.url("apple", "49.6431,-123.2089", nil, nil) ==
               "https://maps.apple.com/?ll=49.6431%2C-123.2089&q=49.6431%2C-123.2089"
    end

    test "searches for an address on one line when there is no latitude and longitude" do
      assert OpenInMaps.url("google", nil, "12 Elm St\n Surrey BC ", nil) ==
               "https://www.google.com/maps/search/?api=1&query=12+Elm+St%2C+Surrey+BC"

      assert OpenInMaps.url("apple", nil, "12 Elm St\n Surrey BC ", nil) ==
               "https://maps.apple.com/?q=12+Elm+St%2C+Surrey+BC"
    end

    test "is nil with nothing to find" do
      assert OpenInMaps.url("google", nil, " ", nil) == nil
      assert OpenInMaps.url("google", "", nil, nil) == nil
    end
  end

  test "names the app in the link, and shows nothing with nothing to find" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.open_in_maps id="maps" app="apple" address="Murrin Park" />
      <.open_in_maps id="none" address={nil} />
      """)

    document = LazyHTML.from_fragment(html)

    assert document |> LazyHTML.query(~s(a#maps[target="_blank"])) |> LazyHTML.text() ==
             "Open in Apple Maps"

    assert document |> LazyHTML.query("#none") |> Enum.count() == 0
  end
end

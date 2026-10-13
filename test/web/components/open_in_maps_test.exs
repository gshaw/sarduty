defmodule Web.Components.OpenInMapsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.OpenInMaps

  alias Web.Components.OpenInMaps

  describe "urls/3" do
    test "pins the latitude and longitude, with Apple's label" do
      assert OpenInMaps.urls("49.6431,-123.2089", "Murrin Park", "Rope practice") == %{
               google: "https://www.google.com/maps/search/?api=1&query=49.6431%2C-123.2089",
               apple: "https://maps.apple.com/?ll=49.6431%2C-123.2089&q=Rope+practice"
             }
    end

    test "labels Apple's pin with the latitude and longitude when there is no label" do
      assert OpenInMaps.urls("49.6431,-123.2089", nil, nil).apple ==
               "https://maps.apple.com/?ll=49.6431%2C-123.2089&q=49.6431%2C-123.2089"
    end

    test "searches for an address on one line when there is no latitude and longitude" do
      assert OpenInMaps.urls(nil, "12 Elm St\n Surrey BC ", nil) == %{
               google: "https://www.google.com/maps/search/?api=1&query=12+Elm+St%2C+Surrey+BC",
               apple: "https://maps.apple.com/?q=12+Elm+St%2C+Surrey+BC"
             }
    end

    test "is nil with nothing to find" do
      assert OpenInMaps.urls(nil, " ", nil) == nil
      assert OpenInMaps.urls("", nil, nil) == nil
    end
  end

  test "offers both apps and a copy of each part of the place" do
    assigns = %{}

    document =
      ~H"""
      <.open_in_maps id="maps" coordinate="49.6431,-123.2089" address="Murrin Park" />
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()

    assert count(document, ~s(#maps[phx-hook="MapPick"] a[data-map-open][target="_blank"])) == 1
    assert count(document, ~s(#maps-google[aria-checked="true"])) == 1
    assert count(document, ~s(#maps-apple[aria-checked="false"])) == 1
    assert count(document, ~s(#maps-copy-coordinate[value="49.6431,-123.2089"])) == 1
    assert count(document, ~s(#maps-copy-address[value="Murrin Park"])) == 1
  end

  test "shows nothing with nothing to find" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.open_in_maps id="maps" address={nil} />
      """)

    assert String.trim(html) == ""
  end

  defp count(document, selector), do: document |> LazyHTML.query(selector) |> Enum.count()
end

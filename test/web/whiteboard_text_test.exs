defmodule Web.WhiteboardTextTest do
  use ExUnit.Case, async: true

  # cspell:ignore sfsar sartopo (South Fraser SAR's quicklinks, from its whiteboard)

  alias App.Model.WhiteboardNote
  alias Web.WhiteboardText

  describe "segments/1" do
    test "web addresses become links, and the full stop after one stays text" do
      assert WhiteboardText.segments("News is at https://sfsar.sharepoint.com/.") == [
               "News is at ",
               {:link, "https://sfsar.sharepoint.com/", "https://sfsar.sharepoint.com/"},
               "."
             ]

      assert WhiteboardText.segments("Quicklinks: sfsar.ca/sartopo sfsar.ca/d4h (for this)") == [
               "Quicklinks: ",
               {:link, "https://sfsar.ca/sartopo", "sfsar.ca/sartopo"},
               " ",
               {:link, "https://sfsar.ca/d4h", "sfsar.ca/d4h"},
               " (for this)"
             ]

      assert WhiteboardText.segments("See www.bcsara.com!") ==
               ["See ", {:link, "https://www.bcsara.com", "www.bcsara.com"}, "!"]
    end

    test "a bare host, an email address, and plain text stay text" do
      for text <- [
            "Applications close June 30 - training.cochair@bcsara.com",
            "Register at bcsara.com today",
            "Bring gloves, e.g. leather ones.",
            "Early morning flights."
          ] do
        assert WhiteboardText.segments(text) == [text]
      end
    end
  end

  test "a note whose text holds its link needs no second one" do
    note = %WhiteboardNote{
      text: "Photos at https://sfsar.sharepoint.com/",
      url: "https://sfsar.sharepoint.com"
    }

    assert WhiteboardText.link_in_text?(note)
    refute WhiteboardText.link_in_text?(%{note | url: "https://forms.cloud.microsoft/x"})
    refute WhiteboardText.link_in_text?(%{note | url: nil})
  end

  test "an organization's note opens with its name" do
    assert WhiteboardText.speaker("BCSARA") == "BCSARA:"
    assert WhiteboardText.speaker(nil) == "Your organization:"
  end
end

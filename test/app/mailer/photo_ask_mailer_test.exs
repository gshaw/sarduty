defmodule App.Mailer.PhotoAskMailerTest do
  use ExUnit.Case, async: true

  alias App.Mailer.PhotoAskMailer

  @member %{name: "Cameron Ruiz"}
  @team %{name: "Coast Range SAR"}
  @url "https://sarduty.test/photos/token"

  defp second(clean_up?) do
    @member |> PhotoAskMailer.paragraphs(@team, nil, nil, @url, clean_up?) |> Enum.at(1)
  end

  # The email that asks for a photo (#1030). While Clean up is available (#1031) any
  # background works, and the email says so.
  test "with Clean up off the email says nothing about the background" do
    assert second(false) ==
             "Coast Range SAR needs a new photo for your ID card. Take one with your phone: it takes a minute."
  end

  test "while Clean up is available any background works" do
    assert second(true) ==
             "Coast Range SAR needs a new photo for your ID card. Take one with your phone: it takes a minute, and any background works."
  end

  test "the rest of the email is the same either way" do
    asker = %{name: "Alex Chen", email: "alex@example.com"}
    off = PhotoAskMailer.paragraphs(@member, @team, asker, "Sunglasses.", @url, false)
    on = PhotoAskMailer.paragraphs(@member, @team, asker, "Sunglasses.", @url, true)

    assert List.delete_at(off, 1) == List.delete_at(on, 1)
    assert {:button, "Add a photo", @url} in on
  end
end

defmodule Web.Components.CoreTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.Core

  describe "flash/1" do
    defp toast(kind, text) do
      assigns = %{flash: %{Atom.to_string(kind) => text}, kind: kind}

      ~H"<.flash kind={@kind} flash={@flash} />"
      |> rendered_to_string()
      |> LazyHTML.from_fragment()
    end

    defp attribute(document, name), do: document |> LazyHTML.attribute(name) |> List.first()

    test "a one-sentence result fades after 6 seconds, as a status" do
      document = toast(:info, "Team settings saved.") |> LazyHTML.query("#flash-info")

      assert attribute(document, "data-seconds") == "6"
      assert attribute(document, "role") == "status"

      assert document |> LazyHTML.query(".toast-title") |> LazyHTML.text() ==
               "Team settings saved."

      assert document |> LazyHTML.query(".toast-sub") |> Enum.empty?()
    end

    test "a second sentence is the subtitle, and gets 10 seconds" do
      document =
        toast(:info, "ID cards saved. Cards on members' phones update in about a minute.")
        |> LazyHTML.query("#flash-info")

      assert attribute(document, "data-seconds") == "10"
      assert document |> LazyHTML.query(".toast-title") |> LazyHTML.text() == "ID cards saved."

      assert document |> LazyHTML.query(".toast-sub") |> LazyHTML.text() ==
               "Cards on members' phones update in about a minute."
    end

    test "an email's dots don't split a sentence" do
      document = toast(:info, "Emailed the ID card to cameron.ruiz@example.com.")
      assert document |> LazyHTML.query(".toast-sub") |> Enum.empty?()
    end

    test "an error has no timer and is an alert" do
      document =
        toast(:error, "D4H refused the key. Save a new one below.")
        |> LazyHTML.query("#flash-error")

      assert attribute(document, "data-seconds") == nil
      assert attribute(document, "role") == "alert"

      assert document |> LazyHTML.query(".toast-sub") |> LazyHTML.text() ==
               "Save a new one below."
    end
  end

  describe "tabs/1" do
    test "marks only the current tab with aria-current" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.tabs label="Member">
          <:tab navigate="/a">Attendance</:tab>
          <:tab navigate="/b" current>Groups</:tab>
          <:tab navigate="/c" current={false}>History</:tab>
        </.tabs>
        """)

      document = LazyHTML.from_fragment(html)

      assert document |> LazyHTML.query(~s(nav.tabs[aria-label="Member"] a)) |> Enum.count() == 3

      assert document
             |> LazyHTML.query(~s(a[aria-current="page"]))
             |> LazyHTML.text()
             |> String.trim() == "Groups"
    end
  end
end

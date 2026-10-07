defmodule Web.Components.CoreTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.Core

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

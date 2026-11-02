defmodule Web.AgentsLiveTest do
  use Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "anyone can read how agents work, from the footer", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/agents")

    assert has_element?(lv, "#agents h1", "How agents work with SAR Duty")
    assert has_element?(lv, "#agents-stays", "not from who is in it")
    assert has_element?(lv, ~s(#footer-agents[href="/agents"]))
  end
end

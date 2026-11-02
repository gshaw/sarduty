defmodule Web.ChangelogLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  test "anyone can read the changelog", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/changelog")

    assert has_element?(lv, "#changelog h1", "SAR Duty changelog")
    assert has_element?(lv, "#changelog h2", "Before Sep 2026")
  end

  test "agents read it as Markdown", %{conn: conn} do
    conn = get(conn, ~p"/changelog.md")

    assert response_content_type(conn, :markdown) =~ "text/markdown"
    assert response(conn, 200) =~ "# SAR Duty changelog"
  end

  test "the footer links to it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#footer-changelog[href="/changelog"]))
  end
end

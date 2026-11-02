defmodule Web.ReportLanguageLiveTest do
  use Web.ConnCase, async: true

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "anyone can read how to write a report", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/agents/reports")

    assert has_element?(lv, "#report-language h1", "How to write a report")
    assert has_element?(lv, "#report-language h3", "activities")
    assert has_element?(lv, ~s(#report-language .breadcrumbs a[href="/agents"]), "Agents")
    assert has_element?(lv, ~s(#report-language a[href="/agents/reports.md"]))
  end

  test "agents read it as Markdown", %{conn: conn} do
    conn = get(conn, ~p"/agents/reports.md")

    assert response_content_type(conn, :markdown) =~ "text/markdown"
    assert response(conn, 200) =~ "# How to write a report"
  end

  test "the editor links to it", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/reports/new")

    assert has_element?(lv, ~s(#report-language-link[href="/agents/reports"]))
  end
end

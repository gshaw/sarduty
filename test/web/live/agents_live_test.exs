defmodule Web.AgentsLiveTest do
  use Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "anyone can read how agents work, from the footer", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/agents")

    assert has_element?(lv, "#agents h1", "How agents work with SAR Duty")
    assert has_element?(lv, "#agents-stays", "how a team is organized")
    assert has_element?(lv, ~s(#footer-agents[href="/agents"]))
  end

  test "each thing agents can do says who decides and links its page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/agents")

    assert has_element?(lv, "#agents-use-reports", "nothing to connect")
    refute has_element?(lv, "#agents-who", "disconnect")

    assert has_element?(
             lv,
             ~s(#agents-use-reports a[href="/agents/reports"]),
             "How to write a report"
           )

    assert has_element?(lv, "#agents-use-id-cards", "Public")
    assert has_element?(lv, ~s(#agents-use-id-cards a[href="/agents/id-cards"]))

    assert has_element?(lv, "#agents-use-forms", "nothing to connect")

    assert has_element?(
             lv,
             ~s(#agents-use-forms a[href="https://github.com/gshaw/sarduty/blob/main/docs/ai-writing.md#forms"])
           )

    assert has_element?(lv, ~s(#agents-use-code a[href="https://github.com/gshaw/sarduty"]))
  end

  test "the lander is Markdown too, linking each page's Markdown", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/agents")
    assert has_element?(lv, ~s(#agents-markdown a[href="/agents.md"]))

    markdown = conn |> get(~p"/agents.md") |> response(200)
    assert markdown =~ "# How agents work with SAR Duty"
    assert markdown =~ "(#{Web.Endpoint.url()}/agents/reports.md)"
    assert markdown =~ "(#{Web.Endpoint.url()}/agents/id-cards.md)"
    assert markdown =~ "[SAR Duty on GitHub](https://github.com/gshaw/sarduty)"
  end
end

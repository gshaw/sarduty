defmodule Web.StyleGuideSearchLiveTest do
  use Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Web.Components.Search

  # The attributes the hook, the CSS, and a screen reader rely on.
  @shared ~w(id class role type name phx-hook phx-change phx-submit aria-label
             aria-autocomplete aria-controls aria-expanded)

  defp attributes(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attributes()
    |> Enum.map(fn attrs -> attrs |> Enum.filter(&(elem(&1, 0) in @shared)) |> Enum.sort() end)
  end

  test "every guide page has the search in its top bar, logged out", %{conn: conn} do
    html = conn |> get(~p"/styles/phone") |> html_response(200)

    assert html =~ ~s(<meta name="csrf-token")
    assert html =~ "data-phx-session"
    assert attributes(html, "#search-input") != []
    assert attributes(html, "#nav-login") != []
  end

  test "it is the team search's markup: the same ids and roles", %{conn: conn} do
    {:ok, lv, html} = live_isolated(conn, Web.StyleGuideSearchLive)

    team =
      render_component(&Search.search_box/1,
        kinds: [:member],
        team: %{subdomain: "x", timezone: "America/Vancouver"}
      )

    for selector <- ["#search", "#search-open", "#search-form", "#search-input", "#search-clear"] do
      assert attributes(html, selector) == attributes(team, selector), selector
    end

    lv |> form("#search-form", %{q: "tel:"}) |> render_change()
    html = render(lv)

    assert attributes(html, "#search-results") == [
             [{"aria-label", "Search results"}, {"id", "search-results"}, {"role", "listbox"}]
           ]

    assert has_element?(lv, "#search-group-components h2", "Components")

    assert has_element?(
             lv,
             ~s{#search-hit-section-phone--in-the-app[role=option][href="/styles/phone#:~:text=In%20the%20app"]}
           )

    assert has_element?(lv, "#search-hit-section-phone--in-the-app b", "tel:")
    refute has_element?(lv, "#search-hit-section-phone--in-the-app[data-phx-link]")
  end

  test "before typing, says what it finds and shows recent picks", %{conn: conn} do
    {:ok, lv, _html} = live_isolated(conn, Web.StyleGuideSearchLive)

    assert has_element?(lv, "#search[data-recent-key=\"sarduty:styles-search-recent\"]")
    assert has_element?(lv, "#search-hint", "Find a page or section by any word")

    render_hook(element(lv, "#search"), "recent", %{"keys" => ["page:phone", "page:gone"]})
    assert has_element?(lv, "#search-group-recent h2", "Recent")
    assert has_element?(lv, ~s{#search-hit-page-phone[data-key="page:phone"]})
  end

  test "says when nothing matches", %{conn: conn} do
    {:ok, lv, _html} = live_isolated(conn, Web.StyleGuideSearchLive)

    lv |> form("#search-form", %{q: "plover quagga"}) |> render_change()

    assert has_element?(lv, "#search-none h2", "Nothing matches “plover quagga”")
    assert has_element?(lv, "#search-none", "examples included")
  end

  test "Enter with nothing picked opens the best result", %{conn: conn} do
    {:ok, lv, _html} = live_isolated(conn, Web.StyleGuideSearchLive)

    assert {:error, {:redirect, %{to: "/styles/phone"}}} =
             lv |> form("#search-form", %{q: "phone"}) |> render_submit()
  end
end

defmodule Web.StyleGuideControllerTest do
  use Web.ConnCase

  alias Web.StyleGuideHTML

  test "GET /styles shows the overview", %{conn: conn} do
    conn = get(conn, ~p"/styles")
    assert html_response(conn, 200) =~ "<h1>Style guide</h1>"
  end

  test "the logo goes to the home page", %{conn: conn} do
    assert html_response(get(conn, ~p"/styles/forms"), 200) =~ ~s(<a href="/" class="brand">)
  end

  defp count(html, selector),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.count()

  test "the side nav lists the groups, the open one marked, then its pages", %{conn: conn} do
    html = html_response(get(conn, ~p"/styles/button"), 200)

    assert count(html, ~s(#side-nav #side-nav-components.is-open)) == 1
    assert count(html, ~s(#side-nav #side-nav-button[aria-current="page"])) == 1
    assert count(html, ~s(#side-nav #side-nav-patterns)) == 1
    assert count(html, ~s(#side-nav #side-nav-colour)) == 0
    assert count(html, ~s(#phone-menu #phone-nav-components.is-open)) == 1
  end

  test "breadcrumbs lead back to the group and the overview", %{conn: conn} do
    html = html_response(get(conn, ~p"/styles/button"), 200)
    assert count(html, ~s(.breadcrumbs a[href="/styles"])) == 1
    assert count(html, ~s(.breadcrumbs a[href="/styles/components"])) == 1
    assert count(html, ~s(.breadcrumbs [aria-current="page"])) == 1

    html = html_response(get(conn, ~p"/styles/components"), 200)
    assert count(html, ~s(.breadcrumbs a[href="/styles"])) == 1
    assert count(html, ~s(.breadcrumbs a[href="/styles/components"])) == 0

    assert count(html_response(get(conn, ~p"/styles"), 200), ".breadcrumbs") == 0
  end

  test "the bar has Log in for a visitor and the switcher once logged in", %{conn: conn} do
    html = html_response(get(conn, ~p"/styles/button"), 200)
    assert count(html, "#nav-login") == 1
    assert count(html, "#team-switcher") == 0

    admin = App.AccountsFixtures.user_fixture(%{is_admin: true})
    html = conn |> log_in_user(admin) |> get(~p"/styles/button") |> html_response(200)
    assert count(html, "#nav-login") == 0
    assert count(html, "#team-switcher #switch-admin") == 1
    assert count(html, "#account-menu") == 1
  end

  test "every group lists its pages", %{conn: conn} do
    for {group, title, _about, pages} <- StyleGuideHTML.groups(), group != :index do
      html = html_response(get(conn, StyleGuideHTML.page_path(group)), 200)
      assert html =~ "<h1>#{title}</h1>"

      for {page, _title, _about} <- pages do
        assert html =~ ~s(href="#{StyleGuideHTML.page_path(page)}")
      end
    end
  end

  test "every page in the guide renders", %{conn: conn} do
    for {_group, _title, _about, pages} <- StyleGuideHTML.groups(),
        {page, title, _about} <- pages,
        page != :index do
      html = html_response(get(conn, StyleGuideHTML.page_path(page)), 200)
      assert html =~ "<title>#{title} · SAR Duty style guide</title>"
    end
  end

  test "the Icons page lists every icon in assets/icons, and the app uses each one" do
    files = for path <- Path.wildcard("assets/icons/*.svg"), do: Path.basename(path, ".svg")
    listed = for {name, _use} <- StyleGuideHTML.icons(), do: name

    assert Enum.sort(listed) == Enum.sort(files),
           "StyleGuideHTML.icons/0 lists one row per file in assets/icons"

    # <.icon> refuses a name with no file. This is the other way: a file nothing uses, found
    # as its name in quotes on a line that mentions an icon.
    lines =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          not String.contains?(path, "style_guide"),
          line <- path |> File.read!() |> String.split("\n"),
          line =~ "icon",
          do: line

    unused = Enum.reject(files, fn name -> Enum.any?(lines, &(&1 =~ ~s("#{name}"))) end)
    assert unused == [], "Nothing uses these; delete them from assets/icons: #{inspect(unused)}"
  end

  test "the Values page shows every Service.Format function", %{conn: conn} do
    shown =
      for {_section, _about, rows} <- StyleGuideHTML.values(), {name, _, _} <- rows, do: name

    missing =
      Service.Format.__info__(:functions) |> Keyword.keys() |> Enum.uniq() |> Kernel.--(shown)

    assert missing == [], "Add these to StyleGuideHTML.values/0: #{inspect(missing)}"
    assert html_response(get(conn, ~p"/styles/values"), 200) =~ ~s(id="value-days-1")
  end

  test "page paths use dashes", %{conn: conn} do
    assert html_response(get(conn, ~p"/styles/side-nav"), 200) =~ "<h1>Side navigation</h1>"
    assert_error_sent 404, fn -> get(conn, "/styles/side_nav") end
  end

  test "an unknown page is not found", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/styles/nope") end
    assert_error_sent 404, fn -> get(conn, "/styles/index") end
  end
end

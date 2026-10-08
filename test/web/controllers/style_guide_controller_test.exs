defmodule Web.StyleGuideControllerTest do
  use Web.ConnCase

  alias Web.StyleGuideHTML

  test "GET /styles shows the overview", %{conn: conn} do
    conn = get(conn, ~p"/styles")
    assert html_response(conn, 200) =~ "<h1>Style guide</h1>"
  end

  test "the logo goes to the home page", %{conn: conn} do
    assert html_response(get(conn, ~p"/styles/input"), 200) =~ ~s(<a href="/" class="brand">)
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

  test "page paths use dashes", %{conn: conn} do
    assert html_response(get(conn, ~p"/styles/back-link"), 200) =~ "<h1>Back link</h1>"
    assert_error_sent 404, fn -> get(conn, "/styles/back_link") end
  end

  test "an unknown page is not found", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/styles/nope") end
    assert_error_sent 404, fn -> get(conn, "/styles/index") end
  end
end

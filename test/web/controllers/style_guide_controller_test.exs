defmodule Web.StyleGuideControllerTest do
  use Web.ConnCase

  test "GET /styles shows the overview", %{conn: conn} do
    conn = get(conn, ~p"/styles")
    assert html_response(conn, 200) =~ "<h1>Style guide</h1>"
  end

  test "every page in the guide renders", %{conn: conn} do
    for {_group, pages} <- Web.StyleGuideHTML.pages(), {page, title} <- pages, page != :index do
      assert html_response(get(conn, "/styles/#{page}"), 200) =~ title
    end
  end

  test "an unknown page is not found", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/styles/nope") end
  end
end

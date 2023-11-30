defmodule SartaskWeb.PageControllerTest do
  use SartaskWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Helpful tools for search and rescue managers"
  end
end

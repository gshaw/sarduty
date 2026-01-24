defmodule Web.HomePageLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  test "renders home page", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "Welcome to"
  end
end

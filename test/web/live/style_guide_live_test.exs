defmodule Web.StyleGuideLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  test "renders style guide", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/styles")

    assert html =~ "Style Guide"
  end
end

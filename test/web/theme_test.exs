defmodule Web.ThemeTest do
  use Web.ConnCase, async: true

  import App.AccountsFixtures
  import Phoenix.LiveViewTest

  test "a fresh device follows the system", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    refute html =~ "data-theme="
    assert theme_colors(html) == ["#13243a", "#0a111b"]
  end

  test "a saved theme renders on the server, browser colour included", %{conn: conn} do
    html = conn |> put_req_cookie("theme", "dark") |> get(~p"/") |> html_response(200)

    assert html =~ ~s{<html lang="en" data-theme="dark">}
    assert theme_colors(html) == ["#0a111b", "#0a111b"]
  end

  test "a cookie that is not light or dark is System", %{conn: conn} do
    html = conn |> put_req_cookie("theme", "\"><script>") |> get(~p"/") |> html_response(200)

    refute html =~ "data-theme="
  end

  test "a LiveView page and the style guide render it too", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> put_req_cookie("theme", "light")

    assert conn |> get(~p"/account") |> html_response(200) =~ ~s{data-theme="light"}
    assert conn |> get(~p"/styles") |> html_response(200) =~ ~s{data-theme="light"}
  end

  test "the account menu has the switch", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")

    for choice <- ["", "light", "dark"] do
      assert has_element?(
               lv,
               ~s{#account-menu #account-theme button[data-theme-choice="#{choice}"]}
             )
    end
  end

  defp theme_colors(html) do
    ~r{<meta name="theme-color" media="[^"]+" content="([^"]+)"}
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
  end
end

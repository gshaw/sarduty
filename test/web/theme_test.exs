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

  test "Account settings has the switch, with this device's theme on", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> put_req_cookie("theme", "dark")
    {:ok, lv, _html} = live(conn, ~p"/account")

    assert has_element?(
             lv,
             ~s{#theme-form[action="/theme"] input[name="return_to"][value="/account"]}
           )

    assert has_element?(lv, "#theme-form-choice-dark[checked]")
    refute has_element?(lv, "#account-menu #theme-form")
  end

  test "a fresh device's Account settings has System on", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")

    assert has_element?(lv, "#theme-form-choice-system[checked]")
  end

  test "saving a theme sets the cookie, says so, and goes back", %{conn: conn} do
    conn = put(conn, ~p"/theme", %{theme: "dark", return_to: "/styles/forms"})

    assert redirected_to(conn) == "/styles/forms"
    assert conn.resp_cookies["theme"].value == "dark"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Dark on this device."
  end

  test "System deletes the cookie", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie("theme", "dark")
      |> put(~p"/theme", %{theme: "system", return_to: "/"})

    assert conn.resp_cookies["theme"].max_age == 0

    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "The theme follows this device's setting."
  end

  test "a background save gets the cookie alone, with no redirect or toast", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-theme-save", "background")
      |> put(~p"/theme", %{theme: "dark", return_to: "/account"})

    assert response(conn, 204) == ""
    assert conn.resp_cookies["theme"].value == "dark"
    refute Phoenix.Flash.get(conn.assigns.flash, :info)
  end

  test "Account settings confirms a background save with a toast", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")

    assert lv |> element("#theme-form") |> render_hook("theme-saved", %{theme: "dark"}) =~
             "Dark on this device."

    assert has_element?(lv, "#theme-form-choice-dark[checked]")
  end

  test "only goes back to a page on this site", %{conn: conn} do
    for to <- ["https://example.com", "//example.com", "/\\example.com", nil] do
      assert conn |> put(~p"/theme", %{theme: "light", return_to: to}) |> redirected_to() == "/"
    end
  end

  defp theme_colors(html) do
    ~r{<meta name="theme-color" media="[^"]+" content="([^"]+)"}
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
  end
end

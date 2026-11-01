defmodule Web.Admin.IntegrationsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "a test runs from its row: a toast says how it went, and Last test keeps it", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    conn = log_in_user(conn, make_admin(user))

    {:ok, lv, _html} = live(conn, ~p"/admin/integrations")
    assert has_element?(lv, "#side-nav-admin-integrations[aria-current=page]")
    assert has_element?(lv, "#integration-email-last", "Never")

    lv |> form("#test-email", %{"to" => "sam@example.com"}) |> render_submit()
    assert render_async(lv) =~ "Test email sent to sam@example.com."
    assert has_element?(lv, "#integration-email-last", "Sent")

    lv |> element("#test-errors") |> render_click()
    assert render_async(lv) =~ "Honeybadger is off on this server."
    assert has_element?(lv, "#integration-errors-last", "Failed")

    {:ok, events, _html} = live(conn, ~p"/admin/events?kind=integration_tested")
    assert render(events) =~ "service: email"
  end

  test "a failed Wallet test goes back to the page with its reason", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    conn = log_in_user(conn, make_admin(user))

    conn = get(conn, ~p"/admin/integrations/apple-pass")
    assert redirected_to(conn) == ~p"/admin/integrations"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Apple Wallet isn't set up"
  end

  test "is a 404 for anyone who isn't a SAR Duty admin", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    conn = log_in_user(conn, user)

    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/admin/integrations") end
    assert_raise Web.Status.NotFound, fn -> get(conn, ~p"/admin/integrations/google-pass") end
  end
end

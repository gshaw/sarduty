defmodule Web.Admin.IntegrationsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.FileStoreOff
  alias App.Model.Event

  setup %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    admin = make_admin(user)
    %{conn: log_in_user(conn, admin), user: admin}
  end

  test "a test runs from its row: a toast says how it went, and the row keeps it", %{conn: conn} do
    Req.Test.stub(App.Adapter.Website, &Plug.Conn.send_resp(&1, 200, "ok"))

    {:ok, lv, _html} = live(conn, ~p"/admin/integrations")
    assert has_element?(lv, "#side-nav-admin-integrations[aria-current=page]")
    assert has_element?(lv, "#integration-website-last", "Never tested")

    lv |> element("#test-website") |> render_click()
    assert render_async(lv) =~ "The website answers."
    assert has_element?(lv, "#integration-website-last .marker-works", "Works")
    assert has_element?(lv, "#integration-website-last", "just now")

    {:ok, events, _html} = live(conn, ~p"/admin/events?kind=integration_tested")
    assert render(events) =~ "service: website"
  end

  test "a test that needs an answer asks it in a dialog first", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/admin/integrations")

    lv |> element("#test-email") |> render_click()
    assert has_element?(lv, "#test-email-dialog[phx-hook=AskDialog]", "Send a test email?")
    assert has_element?(lv, "#test-email-to[value='#{user.email}']")

    # Cancel or Escape: AskDialog sends the cancel event.
    render_hook(lv, "close_dialog", %{})
    refute has_element?(lv, "#test-email-dialog")

    # Send test email: AskDialog sends the confirm event with the dialog's fields.
    lv |> element("#test-email") |> render_click()
    render_hook(lv, "test", %{"service" => "email", "to" => "sam@example.com"})
    refute has_element?(lv, "#test-email-dialog")
    assert render_async(lv) =~ "Test email sent to sam@example.com."
    assert has_element?(lv, "#integration-email-last", "Sent")

    lv |> element("#test-email") |> render_click()
    assert has_element?(lv, "#test-email-to[value='sam@example.com']")
  end

  test "a service this server doesn't have says so, and offers no test", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/integrations")

    # The test server has no Honeybadger reports, no Wallet keys, and files on disk.
    for key <- ["errors", "apple", "google", "files"] do
      assert has_element?(lv, "#integration-#{key}-last", "Not set up here")
      refute has_element?(lv, "#test-#{key}")
    end
  end

  test "Files says how long its last round trip took", %{conn: conn} do
    FileStoreOff.use_s3()

    :integration_tested
    |> Event.record!(data: %{service: "files", outcome: "running"})
    |> Event.put_outcome!("works", 412)

    {:ok, lv, _html} = live(conn, ~p"/admin/integrations")
    assert has_element?(lv, "#integration-files", "Amazon S3, sarduty-files-test")
    assert has_element?(lv, "#integration-files-last-took", "412 ms")
    assert has_element?(lv, "#test-files", "Check files")
  end

  test "a failed Wallet test goes back to the page with its reason", %{conn: conn} do
    conn = get(conn, ~p"/admin/integrations/apple-pass")
    assert redirected_to(conn) == ~p"/admin/integrations"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Apple Wallet isn't set up"
  end

  test "Download test letter sends the PDF Typst made, locked", %{conn: conn} do
    conn = get(conn, ~p"/admin/integrations/typst-letter")
    assert response_content_type(conn, :pdf) =~ "application/pdf"
    assert "%PDF-" <> _ = conn.resp_body
    assert conn.resp_body =~ "/Encrypt"
  end

  test "is a 404 for anyone who isn't a SAR Duty admin" do
    %{user: user} = user_with_team_fixture()
    conn = log_in_user(build_conn(), user)

    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/admin/integrations") end
    assert_raise Web.Status.NotFound, fn -> get(conn, ~p"/admin/integrations/google-pass") end
  end
end

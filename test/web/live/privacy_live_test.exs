defmodule Web.PrivacyLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  alias App.Model.DemoTeam

  test "anyone can read the privacy page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/privacy")

    assert has_element?(lv, "#privacy-page h1", "Privacy")
    assert has_element?(lv, "#privacy-page h2", "Who runs SAR Duty")
    assert has_element?(lv, "#privacy-page p", "Andrew Wallwork")
    assert has_element?(lv, ~s(#privacy-page a[href="mailto:privacy@sarduty.com"]))
  end

  test "it says how long a demo lasts", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/privacy")

    days = Service.Format.days(DemoTeam.days())
    assert has_element?(lv, "#privacy-page p", "deleted, #{days} after you first open it")
  end

  test "the footer links to it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#footer-privacy[href="/privacy"]))
  end
end

defmodule Web.VerifySamplesLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  # The sample cards page (#854), on the verify site.
  setup %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, Web.VerifyHost.host())
      |> put_req_header("fly-client-ip", "10.3.#{System.unique_integer([:positive])}")

    %{conn: conn}
  end

  test "lists a QR code for each answer, and each opens its result", %{conn: conn} do
    for {id, result} <- [
          {"active", "#result-active"},
          {"inactive", "#result-inactive"},
          {"revoked", "#result-revoked"},
          {"not-found", "#result-not-found"},
          {"other-site", "#result-other-site"}
        ] do
      {:ok, lv, _html} = live(conn, ~p"/samples")
      assert has_element?(lv, "#sample-#{id} svg")

      {:ok, result_lv, _html} =
        lv |> element("#sample-#{id}-check") |> render_click() |> follow_redirect(conn)

      assert has_element?(result_lv, result), id
    end
  end

  test "the forged card's QR names a domain nobody can register", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/samples")
    assert has_element?(lv, "#sample-other-site", "verify.sarduty.example")
  end
end

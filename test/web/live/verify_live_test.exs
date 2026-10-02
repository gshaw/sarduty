defmodule Web.VerifyLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MemberCard

  # The verify site is matched by host, like verify.sarduty.com in production. Each test
  # gets its own client IP, since the limit's counters outlive a test.
  setup %{conn: conn} do
    team = team_fixture()
    conn = conn |> Map.put(:host, Web.VerifyHost.host()) |> with_ip(unique_ip())
    %{conn: conn, team: team, member: member_fixture(team)}
  end

  defp unique_ip, do: "10.0.#{System.unique_integer([:positive])}"
  defp with_ip(conn, ip), do: put_req_header(conn, "fly-client-ip", ip)

  # A check by ?code=, which works from a result too, where the form isn't shown.
  defp check(lv, code), do: render_patch(lv, ~p"/?#{[code: code]}")

  test "anyone can open the page without logging in", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, "#check-form")
    assert has_element?(lv, "#scanner")
    assert has_element?(lv, "#verify-footer a", Web.Endpoint.host())
  end

  test "a typed code for a current member shows them as active", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/")

    typed = card.code |> MemberCard.format_code() |> String.downcase()
    lv |> form("#check-form", check: %{code: typed}) |> render_submit()

    assert has_element?(lv, "#result-active")
    assert has_element?(lv, "#result-name", member.name)
    assert has_element?(lv, "#result-facts", "Active")
  end

  test "a scanned code is checked the same way", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/")

    lv |> element("#scanner") |> render_hook("scanned", %{code: card.code})

    assert has_element?(lv, "#result-active")
  end

  test "a card's QR link opens straight to the check", %{conn: conn, member: member} do
    card = member_card_fixture(member)

    path = card.code |> MemberCard.qr_url(Web.VerifyHost.url()) |> URI.parse() |> Map.get(:path)
    {:ok, lv, _html} = live(conn, path)

    assert has_element?(lv, "#result-active")
    assert has_element?(lv, "#result-photo")
    assert has_element?(lv, "#result-check", "address bar")
  end

  test "scanning a card's QR link on this page checks its code", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/")

    link = MemberCard.qr_url(card.code, Web.VerifyHost.url())
    lv |> element("#scanner") |> render_hook("scanned", %{code: link})

    assert_patch(lv, ~p"/#{MemberCard.format_code(card.code)}")
    assert has_element?(lv, "#result-active")
  end

  test "scanning a link to another site flags the card", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/")

    link = "https://sarduty-verify.com/verify/#{MemberCard.format_code(card.code)}"
    lv |> element("#scanner") |> render_hook("scanned", %{code: link})

    assert has_element?(lv, "#result-other-site", "sarduty-verify.com")
    refute has_element?(lv, "#result-active")
  end

  test "a member who left shows as not active", %{conn: conn, team: team} do
    member = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    card = member_card_fixture(member)

    {:ok, lv, _html} = live(conn, ~p"/?#{[code: card.code]}")

    assert has_element?(lv, "#result-inactive", "Left the team Dec 2025")
    assert has_element?(lv, "#result-facts", "Not active")
  end

  test "a cancelled card shows no member details", %{conn: conn, member: member} do
    card = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})

    {:ok, lv, html} = live(conn, ~p"/?#{[code: card.code]}")

    assert has_element?(lv, "#result-revoked")
    refute html =~ member.name
  end

  test "an unknown or malformed code is not found", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/?#{[code: "AAAA-AAAA"]}")
    assert has_element?(lv, "#result-not-found")

    {:ok, lv, _html} = live(conn, ~p"/?#{[code: "not a code"]}")
    assert has_element?(lv, "#result-not-found")
  end

  test "lists the qualifications the team shows on cards", %{
    conn: conn,
    team: team,
    member: member
  } do
    qualification = qualification_fixture(team)
    clause = group_rule_clause_fixture(group_fixture(team), %{name: "First Aid", on_card: true})
    group_rule_clause_qualification_fixture(clause, qualification)
    qualification_award_fixture(qualification, member)
    card = member_card_fixture(member)

    {:ok, lv, _html} = live(conn, ~p"/?#{[code: card.code]}")

    assert has_element?(lv, "#result-qualifications", "First Aid")
  end

  test "a card scanned from before the verify site still checks", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/")

    old_link =
      "HTTPS://#{String.upcase(Web.Endpoint.host())}/VERIFY/#{MemberCard.format_code(card.code)}"

    lv |> element("#scanner") |> render_hook("scanned", %{code: old_link})

    assert has_element?(lv, "#result-active")
  end

  test "the rest of the app isn't on the verify site", %{conn: conn} do
    assert conn |> get("/settings/team") |> redirected_to() ==
             Web.Endpoint.url() <> "/settings/team"

    # One segment reads as a code.
    {:ok, lv, _html} = live(conn, "/login")
    assert has_element?(lv, "#result-not-found")
    refute has_element?(lv, "#login_form")
  end

  describe "the limit on misses" do
    test "the 21st miss shows the limit and doesn't look the code up", %{
      conn: conn,
      member: member
    } do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/")

      for _ <- 1..20, do: check(lv, "ZZZZ-ZZZZ")
      assert has_element?(lv, "#result-not-found")

      check(lv, card.code)
      assert has_element?(lv, "#result-limited", "Wait a few minutes")
      refute has_element?(lv, "#result-active")
    end

    test "a limited IP doesn't stop others", %{conn: conn, member: member} do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/")
      for _ <- 1..21, do: check(lv, "ZZZZ-ZZZZ")
      assert has_element?(lv, "#result-limited")

      other = build_conn() |> Map.put(:host, conn.host) |> with_ip(unique_ip())
      {:ok, lv, _html} = live(other, ~p"/")

      check(lv, card.code)
      assert has_element?(lv, "#result-active")
    end

    test "real codes never count", %{conn: conn, member: member} do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/")

      for _ <- 1..25, do: check(lv, card.code)
      check(lv, "ZZZZ-ZZZZ")

      assert has_element?(lv, "#result-not-found")
    end

    test "a bad link opened directly counts", %{conn: conn} do
      for _ <- 1..10, do: {:ok, _lv, _html} = live(conn, ~p"/ZZZZ-ZZZZ")

      {:ok, lv, _html} = live(conn, ~p"/ZZZZ-ZZZZ")
      assert has_element?(lv, "#result-limited")
    end
  end

  describe "on the app's host" do
    setup %{conn: conn}, do: %{conn: %{conn | host: Web.Endpoint.host()}}

    test "/verify links from before the verify site go there", %{conn: conn} do
      assert conn |> get("/VERIFY/K7Q4-M2XA") |> redirected_to() ==
               Web.VerifyHost.url() <> "/K7Q4-M2XA"

      assert build_conn() |> get("/verify?code=K7Q4M2XA") |> redirected_to() ==
               Web.VerifyHost.url() <> "/?code=K7Q4M2XA"

      assert build_conn() |> get("/verify") |> redirected_to() == Web.VerifyHost.url() <> "/"
    end
  end
end

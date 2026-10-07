defmodule Web.VerifyLetterLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.TaxCreditLetter
  alias App.Operation.ReplaceTaxCreditLetter

  # Like the ID card check: matched by host, with a client IP of its own per test.
  setup %{conn: conn} do
    team =
      %{name: "North Shore Rescue"}
      |> team_fixture()
      |> Ecto.Changeset.change(authorized_by_name: "Pat Lee", authorized_by_phone: "604-555-0100")
      |> App.Repo.update!()

    member = member_fixture(team, %{name: "Mercer, Nadia"})
    conn = conn |> Map.put(:host, Web.VerifyHost.host()) |> with_ip(unique_ip())
    %{conn: conn, team: team, member: member}
  end

  defp unique_ip, do: "10.1.#{System.unique_integer([:positive])}"
  defp with_ip(conn, ip), do: put_req_header(conn, "fly-client-ip", ip)

  defp letter(member, attrs \\ %{}) do
    tax_credit_letter_fixture(
      member,
      Map.merge(
        %{
          ref_id: TaxCreditLetter.generate_ref_id(),
          year: 2025,
          primary_minutes: 212 * 60 + 30,
          secondary_minutes: 18 * 60
        },
        attrs
      )
    )
  end

  test "the start page asks for a reference number and says nothing about ID cards",
       %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/letters")

    assert has_element?(lv, "#check-form")
    refute html =~ "ID card"
  end

  test "a typed reference number shows the hours the team issued",
       %{conn: conn, member: member} do
    letter = letter(member)
    {:ok, lv, _html} = live(conn, ~p"/letters")

    typed = letter.ref_id |> String.replace_prefix("SRVTC-", "") |> String.downcase()
    lv |> form("#check-form", check: %{ref: typed}) |> render_submit()

    assert_patch(lv, ~p"/letters/#{letter.ref_id}")
    assert has_element?(lv, "#result-issued", "Issued by the team")
    assert has_element?(lv, "#result-name", "Mercer, Nadia")
    assert has_element?(lv, "#result-team", "North Shore Rescue")
    assert has_element?(lv, "#result-hours", "212 hours, 30 minutes")
    assert has_element?(lv, "#result-hours", "18 hours")
    assert has_element?(lv, "#result-hours", "230 hours, 30 minutes")
    assert has_element?(lv, "#result-contact", "604-555-0100")
  end

  test "the QR code's link opens straight to the result", %{conn: conn, member: member} do
    letter = letter(member)
    path = letter |> TaxCreditLetter.verify_url(Web.VerifyHost.url()) |> URI.parse()

    {:ok, lv, _html} = live(conn, path.path)

    assert has_element?(lv, "#result-issued")
  end

  test "an unknown reference number is not found", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/letters/SRVTC-ZZZZZZZZ")
    assert has_element?(lv, "#result-not-found")

    {:ok, lv, _html} = live(conn, ~p"/letters/nonsense")
    assert has_element?(lv, "#result-not-found")
  end

  test "a letter without saved hours says to contact the team", %{conn: conn, member: member} do
    letter = letter(member, %{primary_minutes: nil, secondary_minutes: nil})
    {:ok, lv, _html} = live(conn, ~p"/letters/#{letter.ref_id}")

    assert has_element?(lv, "#result-no-hours")
    refute has_element?(lv, "#result-hours")
  end

  describe "a replaced letter" do
    test "its old reference number shows the hours it said, marked replaced",
         %{conn: conn, team: team, member: member} do
      letter = member |> letter() |> App.Repo.preload(member: :team)
      replaced = ReplaceTaxCreditLetter.call(team, letter)

      {:ok, lv, _html} = live(conn, ~p"/letters/#{letter.ref_id}")
      assert has_element?(lv, "#result-replaced", "This letter was replaced")
      assert has_element?(lv, "#result-hours", "230 hours, 30 minutes")

      {:ok, lv, _html} = live(conn, ~p"/letters/#{replaced.ref_id}")
      assert has_element?(lv, "#result-issued")
      assert has_element?(lv, "#result-hours", "0 hours")
    end
  end

  describe "a reference number from before #207" do
    test "needs the member's last name before it shows anything",
         %{conn: conn, member: member} do
      letter = letter(member, %{ref_id: "SRVTC-M4K11"})
      {:ok, lv, html} = live(conn, ~p"/letters/#{letter.ref_id}")

      assert has_element?(lv, "#last-name-form")
      refute html =~ "Mercer"

      lv |> form("#last-name-form", check: %{last_name: "nadia"}) |> render_submit()
      assert has_element?(lv, "#result-not-found")
    end

    test "shows the letter with the right last name", %{conn: conn, member: member} do
      letter(member, %{ref_id: "SRVTC-M4K11"})
      {:ok, lv, _html} = live(conn, ~p"/letters/m4k11")

      lv |> form("#last-name-form", check: %{last_name: "MERCER"}) |> render_submit()
      assert has_element?(lv, "#result-issued", "Issued by the team")
    end
  end

  test "misses share the ID card check's limit", %{conn: conn, member: member} do
    letter = letter(member)

    for _ <- 1..20 do
      {:ok, _lv, _html} = live(conn, ~p"/letters/SRVTC-ZZZZZZZZ")
    end

    {:ok, lv, _html} = live(conn, ~p"/letters/#{letter.ref_id}")
    assert has_element?(lv, "#result-limited", "Wait a few minutes")
    refute has_element?(lv, "#result-issued")
  end
end

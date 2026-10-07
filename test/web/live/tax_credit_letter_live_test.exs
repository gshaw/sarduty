defmodule Web.TaxCreditLetterLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.ReplacedTaxCreditLetter
  alias App.Model.TaxCreditLetter
  alias App.Repo

  test "renders tax credit letter", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    letter = tax_credit_letter_fixture(member)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/tax-credit-letters/#{letter.id}")

    assert html =~ letter.ref_id
  end

  test "emails the letter to the member", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    letter = tax_credit_letter_fixture(member)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/tax-credit-letters/#{letter.id}")

    lv |> element("#email-letter") |> render_click()

    assert_email_sent(fn email -> assert email.to == [{"", member.email}] end)
    assert render(lv) =~ "Emailed the tax credit letter to #{member.email}"
  end

  test "says so when the member has no email", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{email: nil})
    letter = tax_credit_letter_fixture(member)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/tax-credit-letters/#{letter.id}")

    lv |> element("#email-letter") |> render_click()

    assert_no_email_sent()
    assert render(lv) =~ "has no email in D4H"
  end

  describe "hours" do
    setup do
      %{user: user, team: team} = user_with_team_fixture()
      member = member_fixture(team)
      %{user: user, team: team, member: member}
    end

    # 90 minutes of primary hours in `year`.
    defp attend(team, member, year) do
      started_at = year |> Date.new!(3, 1) |> DateTime.new!(~T[17:00:00], "Etc/UTC")
      activity = activity_fixture(team, %{started_at: started_at})

      attendance_fixture(activity, member, %{
        started_at: started_at,
        finished_at: DateTime.add(started_at, 90 * 60)
      })
    end

    test "warns when the current year's hours changed, and replaces the letter on request",
         %{conn: conn, user: user, team: team, member: member} do
      year = TaxCreditLetter.current_year(DateTime.utc_now(), team.timezone)
      attend(team, member, year)

      letter =
        tax_credit_letter_fixture(member, %{year: year, primary_minutes: 60, secondary_minutes: 0})

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/tax-credit-letters/#{letter.id}")

      assert has_element?(lv, "#hours-changed", "This letter says 1 hour")
      assert has_element?(lv, "#hours-changed", "Attendance now adds up to 1h 30m")

      lv |> element("#replace-letter") |> render_click()

      refute has_element?(lv, "#hours-changed")
      assert has_element?(lv, "#letter-hours", "1h 30m")

      replaced = Repo.get!(TaxCreditLetter, letter.id)
      assert {:current, _ref_id} = TaxCreditLetter.parse_ref_id(replaced.ref_id)
      assert replaced.ref_id != letter.ref_id
      assert replaced.primary_minutes == 90
      assert replaced.letter_content =~ "Primary Hours: 1 hour, 30 minutes"
      assert replaced.letter_content =~ "Reference: #{replaced.ref_id}"

      old = Repo.get_by!(ReplacedTaxCreditLetter, tax_credit_letter_id: letter.id)
      assert {old.ref_id, old.primary_minutes} == {letter.ref_id, 60}
      assert_no_email_sent()
    end

    test "an older letter shows both numbers with no warning",
         %{conn: conn, user: user, team: team, member: member} do
      year = TaxCreditLetter.current_year(DateTime.utc_now(), team.timezone) - 1
      attend(team, member, year)

      letter =
        tax_credit_letter_fixture(member, %{
          year: year,
          primary_minutes: 60,
          secondary_minutes: 0,
          letter_content: "Primary Hours: 1 hour"
        })

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/tax-credit-letters/#{letter.id}")

      refute has_element?(lv, "#hours-changed")
      assert has_element?(lv, "#letter-hours", "1 hour")
      assert has_element?(lv, "#attendance-hours", "1h 30m")

      # Nothing changed the letter.
      assert Repo.get!(TaxCreditLetter, letter.id).letter_content == "Primary Hours: 1 hour"
    end
  end
end

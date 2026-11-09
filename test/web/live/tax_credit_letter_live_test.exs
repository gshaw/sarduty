defmodule Web.TaxCreditLetterLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.PublishedPDF
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

    assert html =~ PublishedPDF.format_code(letter.pdf.code)
  end

  test "shows the ID to copy, and a link to verify a current one", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    current = tax_credit_letter_fixture(member, %{code: "K7Q4M2XA9HVB3TN"})
    old = tax_credit_letter_fixture(member, %{code: "SRVTC-M4K11", year: 2020})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters/#{current.id}")
    assert has_element?(lv, "#letter-reference[value='K7Q4M-2XA9H-VB3TN']")
    assert has_element?(lv, "#letter-verify[href='#{Web.VerifyHost.url()}/K7Q4M-2XA9H-VB3TN']")

    # A reference from before #207 can't verify alone.
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters/#{old.id}")
    assert has_element?(lv, "#letter-reference[value='SRVTC-M4K11']")
    refute has_element?(lv, "#letter-verify")
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

    assert_email_sent(fn email ->
      assert email.to == [{"", member.email}]
      assert [%{data: "%PDF-1.7 test letter " <> _ref}] = email.attachments
    end)

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
    assert render(lv) =~ "has no email."
  end

  test "emailing a letter with no PDF publishes it first", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    letter = tax_credit_letter_fixture(member)
    Repo.delete!(letter.pdf)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/tax-credit-letters/#{letter.id}")

    lv |> element("#email-letter") |> render_click()

    assert %{content: "%PDF" <> _rest} = saved = PublishedPDF.letter_attachment(letter)

    assert_email_sent(fn email ->
      assert [%{data: data}] = email.attachments
      assert data == saved.content
    end)
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

      assert has_element?(
               lv,
               ~s(#replace-letter[data-confirm-check="I understand the old letter's verify page says Replaced."])
             )

      lv |> element("#replace-letter") |> render_click()

      refute has_element?(lv, "#hours-changed")
      assert has_element?(lv, "#letter-hours", "1h 30m")

      replaced = TaxCreditLetter |> Repo.get!(letter.id) |> Repo.preload(:pdf)
      assert {:code, _code} = PublishedPDF.parse_code(replaced.pdf.code)
      assert replaced.pdf.code != letter.pdf.code
      assert PublishedPDF.status(Repo.reload!(letter.pdf)) == :replaced
      assert replaced.primary_minutes == 90
      assert replaced.letter_content =~ "Primary Hours: 1h 30m\n"

      assert_no_email_sent()
    end

    test "deletes the letter once the box is ticked", %{
      conn: conn,
      user: user,
      team: team,
      member: member
    } do
      letter = tax_credit_letter_fixture(member, %{year: 2025})

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/tax-credit-letters/#{letter.id}")

      assert has_element?(
               lv,
               ~s(#delete-letter[data-confirm-check="I understand #{PublishedPDF.format_code(letter.pdf.code)} no longer verifies."])
             )

      assert {:error, {:redirect, _}} = lv |> element("#delete-letter") |> render_click()
      refute Repo.get(TaxCreditLetter, letter.id)
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

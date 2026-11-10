defmodule Web.TaxCreditLetterLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    team = signer_fixture(team)
    member = member_fixture(team, %{name: "Sam Doe"})
    # The admin is the team's manager, a member, so "by" lines name them.
    admin = Member.find_by_email(team, user.email, DateTime.utc_now())
    %{conn: log_in_user(conn, user), user: user, team: team, member: member, admin: admin}
  end

  defp letter_path(team, member, year),
    do: ~p"/teams/#{team}/tax-credit-letters/#{year}/members/#{member.id}"

  # 90 minutes of primary hours in `year`.
  defp attend(team, member, year) do
    started_at = year |> Date.new!(3, 1) |> DateTime.new!(~T[17:00:00], "Etc/UTC")
    activity = activity_fixture(team, %{started_at: started_at})

    attendance_fixture(activity, member, %{
      started_at: started_at,
      finished_at: DateTime.add(started_at, 90 * 60)
    })
  end

  test "a published letter: when and who, its ID, Download, page 1, and History (#970)",
       %{conn: conn, team: team, member: member, admin: admin, user: user} do
    letter = tax_credit_letter_fixture(member, %{year: 2025, code: "K7Q4M2XA9HVB3TN"})
    letter |> Ecto.Changeset.change(user_id: user.id) |> Repo.update!()

    {:ok, lv, html} = live(conn, letter_path(team, member, 2025))

    assert html =~ "Sam Doe&#39;s 2025 tax credit letter"
    assert has_element?(lv, "#letter-published", "by #{admin.name}")
    assert has_element?(lv, "#letter-verify[href='#{Web.VerifyHost.url()}/K7Q4M-2XA9H-VB3TN']")

    assert has_element?(
             lv,
             ~s(#letter-download[href="/teams/#{team.subdomain}/pdfs/#{letter.id}"])
           )

    assert has_element?(
             lv,
             ~s(#letter-preview[src="/teams/#{team.subdomain}/pdfs/#{letter.id}/preview.png"])
           )

    assert has_element?(lv, "#letter-email", "Not emailed")
    assert has_element?(lv, "#letter-history-published-#{letter.id}", "K7Q4M-2XA9H-VB3TN")
    assert has_element?(lv, "#letter-history-published-#{letter.id}", admin.name)
    refute has_element?(lv, "#letter-out-of-date")
    refute has_element?(lv, "#replace-letter")
  end

  test "no letter yet: the draft, and Send letter publishes and emails it (#970)",
       %{conn: conn, team: team, member: member} do
    attend(team, member, 2025)

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))

    assert has_element?(lv, "#letter-not-published", "No letter for 2025 yet")
    assert has_element?(lv, "#letter-not-published", "emails it to #{member.email}")

    assert has_element?(
             lv,
             ~s(#letter-preview[src="/teams/#{team.subdomain}/tax-credit-letters/2025/members/#{member.id}/draft.png"])
           )

    assert has_element?(lv, "#letter-hours-now", "1h 30m")

    lv |> element("#send-letter") |> render_click()

    letter = TaxCreditLetter.get_current(member, 2025)
    assert TaxCreditLetter.minutes(letter) == {90, 0}
    assert_email_sent(fn email -> assert email.to == [{"", member.email}] end)
    assert render(lv) =~ "and emailed it to #{member.email}"
    assert has_element?(lv, "#letter-email", "Emailed")
    assert has_element?(lv, "#letter-history-emailed-#{letter.id}")
  end

  test "emails the letter to the member, and keeps when", %{
    conn: conn,
    team: team,
    member: member
  } do
    letter = tax_credit_letter_fixture(member, %{year: 2025})

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))

    assert has_element?(
             lv,
             ~s(#email-letter[data-confirm="Email letter #{PublishedPDF.format_code(letter.code)} to #{member.email}?"])
           )

    lv |> element("#email-letter") |> render_click()

    assert_email_sent(fn email ->
      assert email.to == [{"", member.email}]
      assert [%{data: "%PDF-1.7 test letter " <> _ref}] = email.attachments
    end)

    assert render(lv) =~ "Emailed the letter to #{member.email}"
    letter = Repo.reload!(letter)
    assert letter.email_status == :sent
    assert letter.emailed_at
    assert has_element?(lv, "#letter-email", "Emailed")
  end

  test "a refused email says Did not send at once", %{conn: conn, team: team, member: member} do
    letter = tax_credit_letter_fixture(member, %{year: 2025})
    refusing_mailer_fixture()

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))
    lv |> element("#email-letter") |> render_click()

    assert Repo.reload!(letter).email_status == :failed
    assert has_element?(lv, "#letter-email", "The email did not send")
  end

  test "a member with no email: no Email letter, and the page says why",
       %{conn: conn, team: team} do
    member = member_fixture(team, %{email: nil})
    tax_credit_letter_fixture(member, %{year: 2025})

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))

    refute has_element?(lv, "#email-letter")
    assert has_element?(lv, "#letter-email", "#{member.name} has no email")
  end

  test "Publish again lists what changed, emails the new letter, and History has both",
       %{conn: conn, user: user, team: team, member: member} do
    year = TaxCreditLetter.current_year(DateTime.utc_now(), team.timezone)
    attend(team, member, year)

    letter =
      tax_credit_letter_fixture(member, %{year: year, primary_minutes: 60, secondary_minutes: 0})

    {:ok, lv, _html} = live(conn, letter_path(team, member, year))

    assert has_element?(lv, "#letter-out-of-date", "Primary hours: 1 hour → 1h 30m")
    assert has_element?(lv, "#letter-out-of-date", "Total hours: 1 hour → 1h 30m")
    refute has_element?(lv, "#letter-out-of-date", "Secondary hours")

    assert has_element?(
             lv,
             ~s(#replace-letter[data-confirm-warning$="The new letter is emailed to #{member.email}."])
           )

    lv |> element("#replace-letter") |> render_click()

    new = TaxCreditLetter.get_current(member, year)
    assert new.code != letter.code
    assert new.user_id == user.id
    assert TaxCreditLetter.minutes(new) == {90, 0}
    assert letter |> Repo.reload!() |> PublishedPDF.status() == :replaced
    assert_email_sent(fn email -> assert email.to == [{"", member.email}] end)

    refute has_element?(lv, "#letter-out-of-date")
    assert has_element?(lv, "#letter-history-published_again-#{new.id}")
    assert has_element?(lv, "#letter-history-published-#{letter.id}", "Replaced")
  end

  test "Withdraw ends the letter, and the page offers Send letter again",
       %{conn: conn, user: user, team: team, member: member, admin: admin} do
    letter = tax_credit_letter_fixture(member, %{year: 2025})
    code = PublishedPDF.format_code(letter.code)

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))

    assert has_element?(
             lv,
             ~s(#withdraw-letter[data-confirm-check="I understand #{code} no longer verifies."])
           )

    lv |> element("#withdraw-letter") |> render_click()

    letter = Repo.reload!(letter)
    assert PublishedPDF.status(letter) == :withdrawn
    assert letter.withdrawn_by_id == user.id
    refute TaxCreditLetter.get_current(member, 2025)

    assert has_element?(lv, "#letter-not-published")
    assert has_element?(lv, "#letter-history-withdrawn-#{letter.id}", admin.name)
    refute has_element?(lv, "#letter-history-withdrawn-#{letter.id}", user.email)
    assert has_element?(lv, "#letter-history-published-#{letter.id}", "Withdrawn")
  end

  test "an older letter whose hours changed stays as it is",
       %{conn: conn, team: team, member: member} do
    year = TaxCreditLetter.current_year(DateTime.utc_now(), team.timezone) - 1
    attend(team, member, year)
    tax_credit_letter_fixture(member, %{year: year, primary_minutes: 60, secondary_minutes: 0})

    {:ok, lv, _html} = live(conn, letter_path(team, member, year))

    refute has_element?(lv, "#letter-out-of-date")
    refute has_element?(lv, "#replace-letter")
    assert has_element?(lv, "#letter-hours-now", "1h 30m")
  end

  test "a year that can't have letters is a 404", %{conn: conn, team: team, member: member} do
    assert_raise Web.Status.NotFound, fn -> live(conn, letter_path(team, member, 2013)) end
  end
end

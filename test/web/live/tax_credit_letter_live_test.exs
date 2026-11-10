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
             ~s(#letter-download-published[href="/teams/#{team.subdomain}/pdfs/#{letter.id}"])
           )

    # Page 1 is open under the box, as nothing follows it.
    assert has_element?(
             lv,
             ~s(#letter-page-1[open] #letter-preview[src="/teams/#{team.subdomain}/pdfs/#{letter.id}/preview.png"])
           )

    assert has_element?(lv, "#letter-email", "Not emailed")
    assert has_element?(lv, "#letter-history-published-#{letter.id}", "K7Q4M-2XA9H-VB3TN")
    assert has_element?(lv, "#letter-history-published-#{letter.id}", admin.name)
    refute has_element?(lv, "#letter-out-of-date")
    # Sam has no hours in 2025, so Email isn't offered.
    refute has_element?(lv, "#email-letter")
    assert has_element?(lv, "#withdraw-letter.btn-danger")
  end

  test "no letter yet: the draft, and Email letter publishes it, then emails it (#995)",
       %{conn: conn, team: team, member: member} do
    attend(team, member, 2025)

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))

    assert has_element?(lv, "#letter-not-published", "No letter for 2025 yet")

    assert has_element?(
             lv,
             ~s(#letter-page-1[open] #letter-preview[src="/teams/#{team.subdomain}/tax-credit-letters/2025/members/#{member.id}/draft.png"])
           )

    assert has_element?(lv, "#letter-hours-now", "1h 30m")

    assert has_element?(
             lv,
             ~s(#email-letter.btn-primary[data-confirm="Email Sam Doe's letter to #{member.email}? There is no letter yet, so one with 1h 30m is published first."])
           )

    lv |> element("#email-letter") |> render_click()

    letter = TaxCreditLetter.get_current(member, 2025)
    assert TaxCreditLetter.minutes(letter) == {90, 0}
    assert_email_sent(fn email -> assert email.to == [{"", member.email}] end)

    assert has_element?(
             lv,
             "#flash-info",
             "Published letter #{PublishedPDF.format_code(letter.code)} and emailed it to #{member.email}."
           )

    assert has_element?(lv, "#letter-email", "Emailed")
    # Emails aren't History: the Published section says where it went.
    refute has_element?(lv, "#letter-history-emailed-#{letter.id}")
  end

  test "emails an up-to-date letter as it is, and keeps when", %{
    conn: conn,
    team: team,
    member: member
  } do
    attend(team, member, 2025)
    letter = tax_credit_letter_fixture(member, %{year: 2025})

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))

    assert has_element?(
             lv,
             ~s(#email-letter[data-confirm="Email Sam Doe's letter to #{member.email}?"])
           )

    lv |> element("#email-letter") |> render_click()

    assert_email_sent(fn email ->
      assert email.to == [{"", member.email}]
      assert [%{data: "%PDF-1.7 test letter " <> _ref}] = email.attachments
    end)

    assert has_element?(lv, "#flash-info", "Emailed the letter to #{member.email}.")
    letter = Repo.reload!(letter)
    assert letter.email_status == :sent
    assert letter.emailed_at
    assert TaxCreditLetter.get_current(member, 2025).id == letter.id
    assert has_element?(lv, "#letter-email", "Emailed")

    # Emailed, it goes again, as it was published.
    assert has_element?(lv, ~s(#email-letter[data-confirm$="goes again as it was published."]))
  end

  test "a refused email says Did not send at once", %{conn: conn, team: team, member: member} do
    attend(team, member, 2025)
    letter = tax_credit_letter_fixture(member, %{year: 2025})
    refusing_mailer_fixture()

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))
    lv |> element("#email-letter") |> render_click()

    assert Repo.reload!(letter).email_status == :failed
    assert has_element?(lv, "#letter-email", "The email did not send")
  end

  test "a member with no email gets Publish letter, the same action, on Your membership only",
       %{conn: conn, team: team} do
    member = member_fixture(team, %{name: "Blake Morrison", email: nil})
    attend(team, member, 2025)

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))

    assert has_element?(
             lv,
             ~s(#email-letter[data-confirm="Publish Blake Morrison's letter? Blake has no email, so it goes on Your membership only."]),
             "Publish letter"
           )

    lv |> element("#email-letter") |> render_click()

    letter = TaxCreditLetter.get_current(member, 2025)
    assert letter.email_status == nil
    assert_no_email_sent()

    assert has_element?(
             lv,
             "#flash-info",
             "Published letter #{PublishedPDF.format_code(letter.code)}. Blake has no email, so it is on Your membership only."
           )

    # Up to date and no email: nothing more to do.
    refute has_element?(lv, "#email-letter")
    assert has_element?(lv, "#letter-email", "Blake Morrison has no email.")
  end

  test "out of date: a banner says what changed, and Email letter publishes a new one first",
       %{conn: conn, user: user, team: team, member: member} do
    # March: last year's letters are out and still open (TaxCreditLetter.closed?/3).
    App.Clock.freeze(~U[2026-03-02 20:00:00Z])
    year = 2025
    attend(team, member, year)

    letter =
      tax_credit_letter_fixture(member, %{
        year: year,
        primary_minutes: 60,
        secondary_minutes: 0,
        email_status: :sent
      })

    {:ok, lv, _html} = live(conn, letter_path(team, member, year))

    assert has_element?(
             lv,
             "#letter-out-of-date.banner-warning",
             "Published today, this letter would read:"
           )

    assert has_element?(lv, "#letter-out-of-date", "Primary hours: 1 hour → 1h 30m")
    assert has_element?(lv, "#letter-out-of-date", "Total hours: 1 hour → 1h 30m")
    refute has_element?(lv, "#letter-out-of-date", "Secondary hours")
    assert has_element?(lv, "#letter-out-of-date", "Email letter makes a new one and sends it.")
    refute has_element?(lv, "#replace-letter")
    # Plain, beside Download PDF: no button is yellow, and its confirm says what it does.
    refute has_element?(lv, "#email-letter.btn-primary")

    assert has_element?(
             lv,
             ~s(#email-letter[data-confirm="Email Sam Doe's letter to #{member.email}? It is out of date, so a new letter with 1h 30m is published first. The old one then verifies as Replaced."])
           )

    lv |> element("#email-letter") |> render_click()

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

  test "Withdraw ends the letter, and the page offers Email letter again",
       %{conn: conn, user: user, team: team, member: member, admin: admin} do
    attend(team, member, 2025)
    letter = tax_credit_letter_fixture(member, %{year: 2025, email_status: :sent})
    code = PublishedPDF.format_code(letter.code)

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))

    assert has_element?(
             lv,
             ~s(#withdraw-letter[data-confirm="Withdraw Sam Doe's letter #{code}? Nothing takes its place. Sam lists under No letter again."])
           )

    assert has_element?(
             lv,
             ~s(#withdraw-letter[data-confirm-warning="Sam has it by email. Its verify page will say Withdrawn."])
           )

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
    assert has_element?(lv, "#email-letter", "Email letter")
    assert has_element?(lv, "#letter-history-withdrawn-#{letter.id}", admin.name)
    refute has_element?(lv, "#letter-history-withdrawn-#{letter.id}", user.email)
    assert has_element?(lv, "#letter-history-published-#{letter.id}", "Withdrawn")
  end

  test "a closed year's letter whose hours changed stays as it is, and emails as published",
       %{conn: conn, team: team, member: member} do
    year = TaxCreditLetter.current_year(DateTime.utc_now(), team.timezone) - 1
    attend(team, member, year)
    tax_credit_letter_fixture(member, %{year: year, primary_minutes: 60, secondary_minutes: 0})

    {:ok, lv, _html} = live(conn, letter_path(team, member, year))

    refute has_element?(lv, "#letter-out-of-date")
    assert has_element?(lv, "#letter-hours-now", "1h 30m")

    assert has_element?(
             lv,
             ~s(#email-letter[data-confirm="Email Sam Doe's letter to #{member.email}?"])
           )
  end

  test "a year that isn't over is emailed early, after a box that says so (#995)",
       %{conn: conn, team: team, member: member} do
    App.Clock.freeze(~U[2026-11-10 20:00:00Z])
    attend(team, member, 2026)

    # One published earlier, and out of date since: Email replaces it, and Withdraw works.
    letter =
      tax_credit_letter_fixture(member, %{year: 2026, primary_minutes: 60, secondary_minutes: 0})

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2026))
    refute has_element?(lv, "#letter-year-open")
    assert has_element?(lv, "#withdraw-letter")
    assert has_element?(lv, "#letter-out-of-date", "Email letter makes a new one and sends it.")

    assert has_element?(
             lv,
             ~s(#email-letter[data-confirm-check="I know the 2026 tax year isn't over. I'm emailing early to test."])
           )

    assert has_element?(
             lv,
             ~s(#email-letter[data-confirm*="a new letter with 1h 30m so far is published first"])
           )

    lv |> element("#email-letter") |> render_click()
    assert has_element?(lv, "#flash-info", "and emailed it to #{member.email}.")
    assert letter |> Repo.reload!() |> PublishedPDF.status() == :replaced
  end

  test "what the letter needs is a warning banner, and the page has no Email letter (#995)",
       %{conn: conn, team: team, member: member} do
    attend(team, member, 2025)
    team |> Ecto.Changeset.change(authorized_by_title: nil) |> Repo.update!()
    message = "This letter cannot be emailed without the signer's title."

    {:ok, lv, _html} = live(conn, letter_path(team, member, 2025))

    assert has_element?(lv, "#letter-needed.banner-warning", "Needed to email")
    assert has_element?(lv, "#letter-needed", message)

    assert has_element?(
             lv,
             ~s(#letter-needed-fix[href="/teams/#{team.subdomain}/settings/signer"]),
             "team settings"
           )

    refute has_element?(lv, "#email-letter")

    # A stale page's click is refused by the operation.
    render_click(lv, "email", %{})
    assert has_element?(lv, "#flash-error", message)
    refute TaxCreditLetter.get_current(member, 2025)

    # With no email the words follow Publish letter, the action it would be.
    blake = member_fixture(team, %{name: "Blake Morrison", email: nil})
    attend(team, blake, 2025)
    {:ok, lv, _html} = live(conn, letter_path(team, blake, 2025))
    assert has_element?(lv, "#letter-needed", "Needed to publish")

    assert has_element?(
             lv,
             "#letter-needed",
             "This letter cannot be published without the signer's title."
           )

    refute has_element?(lv, "#email-letter")

    # An up-to-date letter goes again as it is, so it needs nothing.
    casey = member_fixture(team, %{name: "Casey Dhillon"})
    attend(team, casey, 2025)
    tax_credit_letter_fixture(casey, %{year: 2025, email_status: :sent})
    {:ok, lv, _html} = live(conn, letter_path(team, casey, 2025))
    refute has_element?(lv, "#letter-needed")
    assert has_element?(lv, "#email-letter[data-confirm]", "Email letter")
  end

  test "a year that can't have letters is a 404", %{conn: conn, team: team, member: member} do
    assert_raise Web.Status.NotFound, fn -> live(conn, letter_path(team, member, 2013)) end
  end
end

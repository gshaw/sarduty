defmodule Web.TaxCreditLetterCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.Event
  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.EmailTaxCreditLetters
  alias App.Operation.SaveTeamSignature
  alias App.Repo
  alias App.Worker.EmailTaxCreditLetterWorker

  test "renders tax credit letters collection", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    _member = member_fixture(team)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/tax-credit-letters")

    assert html =~ "tax credit letters"
  end

  test "shows no member ID, and an old ID sort link sorts by total", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/tax-credit-letters?sort=id&filter=none")

    assert has_element?(lv, "#member_collection", member.name)
    refute has_element?(lv, "#member_collection th", "ID")
    refute has_element?(lv, "#member_collection", member.ref_id)
  end

  describe "check, then act (#970)" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      %{conn: log_in_user(conn, user), team: signer_fixture(team)}
    end

    # Checks `members` and picks `choice`, as the person does.
    defp check(lv, members, choice) do
      lv
      |> form("#letters-form", %{
        "member_ids" => Enum.map(members, &to_string(&1.id)),
        "choice" => choice
      })
      |> render_change()
    end

    defp apply_choice(lv, members, choice) do
      check(lv, members, choice)

      lv
      |> form("#letters-form", %{
        "member_ids" => Enum.map(members, &to_string(&1.id)),
        "choice" => choice
      })
      |> render_submit()
    end

    # 90 minutes of primary hours in 2025.
    defp attend(team, member) do
      activity = activity_fixture(team, %{started_at: ~U[2025-03-01 17:00:00Z]})

      attendance_fixture(activity, member, %{
        started_at: ~U[2025-03-01 17:00:00Z],
        finished_at: ~U[2025-03-01 18:30:00Z]
      })
    end

    test "Email letters emails each checked member their latest letter, publishing first when needed (#995)",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      blake = member_fixture(team, %{name: "Blake", email: nil})
      casey = member_fixture(team, %{name: "Casey"})
      devon = member_fixture(team, %{name: "Devon"})
      eli = member_fixture(team, %{name: "Eli"})
      _no_hours = member_fixture(team, %{name: "Finn"})
      for member <- [avery, blake, casey, devon, eli], do: attend(team, member)
      sent = tax_credit_letter_fixture(casey, %{year: 2025, email_status: :sent})

      old =
        tax_credit_letter_fixture(eli, %{year: 2025, primary_minutes: 60, secondary_minutes: 0})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")

      assert has_element?(lv, "#letters-apply[disabled]")
      assert has_element?(lv, "#letters-bar-hint", "Check members, then select what to do.")
      refute has_element?(lv, "#letters-year-open")
      # Avery, Blake, Devon with no letter, and Eli's out of date. Casey's was emailed.
      assert has_element?(lv, "#letter-view-to_email", "4")

      check(lv, [avery, blake, casey, eli], "email")
      assert has_element?(lv, "#letters-apply", "Email 3 letters")

      assert has_element?(
               lv,
               "#letters-choice",
               "Emails the 3 checked their latest letter. A missing or out-of-date letter is published first. 1 with no email gets theirs on Your membership only."
             )

      lines =
        Jason.encode!([
          "1 gets their first letter.",
          "1 gets a new letter in place of one out of date. Their old letter will verify as Replaced.",
          "1 gets their letter again.",
          "Not emailed: Blake has no email. The letter goes on Your membership only."
        ])

      assert has_element?(lv, ~s(#letters-apply[data-confirm-list='#{lines}']))

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm="Email 3 tax credit letters for 2025? Each member gets their latest letter as a PDF."])
             )

      apply_choice(lv, [avery, blake, casey, eli], "email")

      assert has_element?(lv, "#letters-emailed", "Emailing 3 tax credit letters for 2025.")
      assert has_element?(lv, "#letters-emailed", "3 were published first.")
      assert has_element?(lv, "#letters-not-emailed", "Blake")
      refute has_element?(lv, "#letters-select-#{avery.id}[checked]")

      for member <- [avery, casey, eli],
          do: assert_email_sent(fn email -> assert email.to == [{"", member.email}] end)

      assert_no_email_sent()

      current = from l in PublishedPDF, where: l.year == 2025 and is_nil(l.replaced_by_id)

      assert current |> select([l], l.member_id) |> Repo.all() |> Enum.sort() ==
               Enum.sort([avery.id, blake.id, casey.id, eli.id])

      # Casey's up-to-date letter went again, as it was; Eli's old one says Replaced.
      assert Repo.reload!(sent).replaced_by_id == nil
      assert old |> Repo.reload!() |> PublishedPDF.status() == :replaced
      assert eli |> TaxCreditLetter.get_current(2025) |> TaxCreditLetter.minutes() == {90, 0}
      assert Event.get_last(:tax_credit_letters_sent).data["published"] == 3

      # Each email is its own job, which ran inline, and the letter says it went.
      statuses =
        from l in current, select: {l.member_id, l.email_status}

      assert statuses |> Repo.all() |> Map.new() ==
               %{avery.id => :sent, blake.id => nil, casey.id => :sent, eli.id => :sent}

      refute has_element?(lv, "#hours-changed-#{eli.id}")
    end

    test "a letter whose email failed every time says so in its row",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      attend(team, avery)
      refusing_mailer_fixture()

      EmailTaxCreditLetters.run(team, 2025, [avery.id], nil)
      letter = Repo.get_by!(PublishedPDF, member_id: avery.id)
      assert letter.email_status == :sending

      job = %Oban.Job{args: %{"published_pdf_id" => letter.id}, attempt: 5, max_attempts: 5}
      assert {:error, _reason} = EmailTaxCreditLetterWorker.perform(job)
      assert Repo.reload!(letter).email_status == :failed

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      assert has_element?(lv, "#letter-state-#{avery.id}", "Not emailed")
      assert has_element?(lv, "#letter-email-failed-#{avery.id}", "Did not send")
      assert has_element?(lv, "#letter-view-not_emailed", "1")
    end

    test "the letter switch counts the search's matches (#935) and lists one part",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      blake = member_fixture(team, %{name: "Blake"})
      casey = member_fixture(team, %{name: "Casey"})
      for member <- [avery, blake, casey], do: attend(team, member)
      tax_credit_letter_fixture(casey, %{year: 2025})

      {:ok, lv, _html} =
        live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any&q=ver")

      # "ver" finds Avery only, who has no letter yet.
      assert has_element?(lv, "#letter-view-all[aria-current]", "1")
      assert has_element?(lv, "#letter-view-to_email", "1")
      assert has_element?(lv, "#letter-view-none", "1")
      assert has_element?(lv, "#letter-view-not_emailed", "0")
      assert has_element?(lv, "#letter-view-changed", "0")

      lv |> element("#letter-view-none") |> render_click()
      assert has_element?(lv, "#letter-view-none[aria-current]")
      assert has_element?(lv, "#member_collection", "Avery")

      {:ok, lv, _html} =
        live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any&letter=none")

      assert has_element?(lv, "#member_collection", "Blake")
      refute has_element?(lv, "#member_collection", "Casey")
    end

    test "each name opens the member's letter for the year, and Letter says where it is (#970)",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      blake = member_fixture(team, %{name: "Blake", email: nil})
      casey = member_fixture(team, %{name: "Casey"})
      devon = member_fixture(team, %{name: "Devon"})
      for member <- [avery, blake, casey, devon], do: attend(team, member)
      tax_credit_letter_fixture(blake, %{year: 2025})
      tax_credit_letter_fixture(casey, %{year: 2025, email_status: :sent})
      tax_credit_letter_fixture(devon, %{year: 2025, primary_minutes: 60, secondary_minutes: 0})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")

      assert has_element?(
               lv,
               ~s(#member_collection a[href="/teams/#{team.subdomain}/tax-credit-letters/2025/members/#{avery.id}"]),
               "Avery"
             )

      assert has_element?(lv, "#letter-state-#{blake.id}", "Not emailed")
      assert has_element?(lv, "#letter-no-email-#{blake.id}", "No email")
      assert has_element?(lv, "#letter-state-#{casey.id}", "Emailed")
      assert has_element?(lv, "#hours-changed-#{devon.id}", "Out of date")
      refute has_element?(lv, "#member_collection th", "Email")

      # Not emailed is a to-do: Blake and Devon. Devon is out of date too. To email has
      # Avery and Devon: Blake's letter is up to date, and he has no email.
      assert has_element?(lv, "#letter-view-not_emailed", "2")
      assert has_element?(lv, "#letter-view-changed", "1")
      assert has_element?(lv, "#letter-view-to_email", "2")

      # An old link to the Letter part shows All.
      {:ok, lv, _html} =
        live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any&letter=made")

      assert has_element?(lv, "#letter-view-all[aria-current]", "4")
    end

    test "Email's check counts who gets the email, not the letters", %{conn: conn, team: team} do
      members =
        for n <- 1..11,
            do:
              member_fixture(team, %{
                name: "Member #{n}",
                email: if(n > 1, do: "m#{n}@example.com")
              })

      for member <- members, do: attend(team, member)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      check(lv, members, "email")

      assert has_element?(lv, "#letters-apply", "Email 10 letters")

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm-check="I understand 10 members get this email."])
             )

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm-warning="Emails cannot be taken back."])
             )

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm-list*="Not emailed: Member 1 has no email."])
             )
    end

    # Its letters would need publishing again once it ends (#995).
    test "a year that isn't over can't be emailed, and says when it can", %{
      conn: conn,
      team: team
    } do
      year = Service.YearRange.year_in(DateTime.utc_now(), team.timezone)
      avery = member_fixture(team, %{name: "Avery"})
      {start, _finish} = Service.YearRange.bounds(year, team.timezone)

      activity =
        activity_fixture(team, %{started_at: start, finished_at: DateTime.add(start, 90, :minute)})

      attendance_fixture(activity, avery)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=#{year}&filter=any")
      when_text = "#{year} letters can be emailed from January 1, #{year + 1}."
      assert has_element?(lv, "#letters-year-open", when_text)
      refute has_element?(lv, "#letters-year-open.warning-text")

      check(lv, [avery], "email")
      refute has_element?(lv, "#letters-apply[disabled]")
      refute has_element?(lv, ~s(#letters-apply[data-confirm*="once the year ends"]))
      apply_choice(lv, [avery], "email")

      assert has_element?(lv, "#flash-error", when_text)
      refute Repo.exists?(PublishedPDF)

      user = App.AccountsFixtures.user_fixture()
      assert EmailTaxCreditLetters.call(team, year, [avery.id], user) == {:error, when_text}

      assert %{refused: [{nil, ^when_text}], published: 0} =
               EmailTaxCreditLetters.run(team, year, [avery.id], nil)
    end

    test "says what letters need to publish, with the tab that fills it (#995)",
         %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025")
      refute has_element?(lv, "#letters-needed")

      {:ok, _team} = SaveTeamSignature.call(team, nil)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025")
      # Letters have no Publish: the words say what Email does.
      assert has_element?(lv, "#letters-needed", "Needed to email")

      assert has_element?(
               lv,
               "#letters-needed",
               "Letters cannot be emailed without the signer's signature."
             )

      assert has_element?(
               lv,
               ~s(#letters-needed-fix[href="/teams/#{team.subdomain}/settings/signer"]),
               "team settings"
             )

      # Email stays on, and says the same when it would publish.
      avery = member_fixture(team, %{name: "Avery"})
      attend(team, avery)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      apply_choice(lv, [avery], "email")

      assert has_element?(
               lv,
               "#flash-error",
               "Letters cannot be emailed without the signer's signature."
             )

      refute Repo.exists?(PublishedPDF)

      # The job refuses it too.
      team = Repo.reload!(team)

      assert %{published: 0, refused: [{_avery, "This letter cannot be emailed" <> _}]} =
               EmailTaxCreditLetters.run(team, 2025, [avery.id], nil)
    end

    test "a choice that fits none of the checked greys out and says why",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=none")
      check(lv, [avery], "email")

      assert has_element?(lv, ~s(#letters-choice input[value="email"][disabled]))
      assert has_element?(lv, "#letters-choice", "The member checked cannot get a letter.")
      assert has_element?(lv, ~s(#letters-choice input[value="withdraw"][disabled]))
      assert has_element?(lv, "#letters-choice", "The member checked has no letter.")
    end

    test "Withdraw letters names up to 3, asks for the box from 1, and nothing takes their place",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      blake = member_fixture(team, %{name: "Blake"})
      casey = member_fixture(team, %{name: "Casey"})
      for member <- [avery, blake, casey], do: attend(team, member)
      emailed = tax_credit_letter_fixture(blake, %{year: 2025, email_status: :sent})
      never = tax_credit_letter_fixture(casey, %{year: 2025})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      check(lv, [avery, blake, casey], "withdraw")

      assert has_element?(lv, "#letters-apply.btn-danger", "Withdraw 2 letters")

      assert has_element?(
               lv,
               "#letters-choice",
               "Withdraws the letters of the 2 checked with one. Nothing takes their place. 1 has no letter."
             )

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm="Withdraw the 2025 letters of Blake and Casey? Nothing takes their place. They list under No letter again."])
             )

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm-warning="Blake has theirs by email. Its verify page will say Withdrawn."])
             )

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm-check="I understand 2 letters no longer verify."])
             )

      apply_choice(lv, [avery, blake, casey], "withdraw")

      assert has_element?(lv, "#flash-info", "Withdrew 2 letters.")
      assert emailed |> Repo.reload!() |> PublishedPDF.status() == :withdrawn
      assert never |> Repo.reload!() |> PublishedPDF.status() == :withdrawn
      assert has_element?(lv, "#letter-view-none", "3")
    end

    test "Withdraw letters for 4 or more counts a line per group", %{conn: conn, team: team} do
      members = for name <- ~w(Avery Blake Casey Devon), do: member_fixture(team, %{name: name})
      for member <- members, do: attend(team, member)
      [avery, blake, casey, devon] = members

      for member <- [avery, blake, casey],
          do: tax_credit_letter_fixture(member, %{year: 2025, email_status: :sent})

      tax_credit_letter_fixture(devon, %{year: 2025})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      check(lv, members, "withdraw")

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm^="Withdraw 4 tax credit letters for 2025?"])
             )

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm-list*="3 were emailed. Their verify pages will say Withdrawn."])
             )

      assert has_element?(lv, ~s(#letters-apply[data-confirm-list*="Devon's was never emailed."]))

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm-check="I understand 4 letters no longer verify."])
             )
    end

    test "a filter that hides a checked row unchecks it", %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      blake = member_fixture(team, %{name: "Blake"})
      for member <- [avery, blake], do: attend(team, member)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      check(lv, [avery, blake], "email")
      assert has_element?(lv, "#letters-apply", "Email 2 letters")

      lv
      |> element("#tax_credit_letter_filter_form")
      |> render_change(%{"form" => %{"q" => "ave"}})

      assert has_element?(lv, "#letters-apply", "Email 1 letter")
    end

    test "never makes a letter for another team's member", %{team: team} do
      other_team = team_fixture()
      outsider = member_fixture(other_team)
      attend(other_team, outsider)

      summary = EmailTaxCreditLetters.run(team, 2025, [outsider.id], nil)

      assert summary.published == 0
      assert Repo.aggregate(PublishedPDF, :count) == 0
    end
  end
end

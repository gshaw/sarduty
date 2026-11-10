defmodule Web.TaxCreditLetterCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.Event
  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.CreateTaxCreditLetters
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

    test "Send letters creates and emails a letter for each checked member with none",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      blake = member_fixture(team, %{name: "Blake", email: nil})
      casey = member_fixture(team, %{name: "Casey"})
      _no_hours = member_fixture(team, %{name: "Devon"})
      for member <- [avery, blake, casey], do: attend(team, member)
      had = tax_credit_letter_fixture(casey, %{year: 2025})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")

      assert has_element?(lv, "#letters-apply[disabled]")
      assert has_element?(lv, "#letters-bar-hint", "Check members, then select what to do.")

      # Casey has a letter, so Send letters counts 2 of the 3 checked.
      check(lv, [avery, blake, casey], "send")
      assert has_element?(lv, "#letters-apply", "Send 2 letters")
      assert has_element?(lv, "#letters-choice", "to the 2 checked with no letter")

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm$="No email, so not emailed: Blake."])
             )

      apply_choice(lv, [avery, blake, casey], "send")

      assert has_element?(
               lv,
               "#letters-sent",
               "2 tax credit letters created for 2025. Emailing 1 of them now."
             )

      assert has_element?(lv, "#letters-no-email", "Blake")
      refute has_element?(lv, "#letters-select-#{avery.id}[checked]")

      assert_email_sent(fn email -> assert email.to == [{"", avery.email}] end)
      assert_no_email_sent()

      query = from l in PublishedPDF, where: l.year == 2025, select: l.member_id
      assert query |> Repo.all() |> Enum.sort() == Enum.sort([avery.id, blake.id, casey.id])
      assert Repo.get!(PublishedPDF, had.id).inserted_at == had.inserted_at
      assert Event.get_last(:tax_credit_letters_sent).data["created"] == 2

      # Each email is its own job, which ran inline, and the letter says it went.
      statuses =
        from l in PublishedPDF, where: l.year == 2025, select: {l.member_id, l.email_status}

      assert statuses |> Repo.all() |> Map.new() ==
               %{avery.id => :sent, blake.id => nil, casey.id => nil}
    end

    test "a letter whose email failed every time says so in its row",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      attend(team, avery)
      refusing_mailer_fixture()

      CreateTaxCreditLetters.call(team, 2025, [avery.id])
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

      # Not emailed is a to-do: Blake and Devon. Devon is out of date too.
      assert has_element?(lv, "#letter-view-not_emailed", "2")
      assert has_element?(lv, "#letter-view-changed", "1")

      # An old link to the Letter part shows All.
      {:ok, lv, _html} =
        live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any&letter=made")

      assert has_element?(lv, "#letter-view-all[aria-current]", "4")
    end

    test "the send's check counts who gets the email, not the letters", %{conn: conn, team: team} do
      members =
        for n <- 1..11,
            do:
              member_fixture(team, %{
                name: "Member #{n}",
                email: if(n > 1, do: "m#{n}@example.com")
              })

      for member <- members, do: attend(team, member)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      check(lv, members, "send")

      assert has_element?(lv, "#letters-apply", "Send 11 letters")

      assert has_element?(
               lv,
               ~s(#letters-apply[data-confirm-check="I understand 10 members get this email."])
             )

      assert has_element?(lv, ~s(#letters-apply[data-confirm-list*="not emailed: Member 1."]))
    end

    test "says what letters need to publish, with the tab that fills it (#995)",
         %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025")
      refute has_element?(lv, "#letters-needed")

      {:ok, _team} = SaveTeamSignature.call(team, nil)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025")

      assert has_element?(
               lv,
               "#letters-needed",
               "Letters cannot be published without the signer's signature."
             )

      assert has_element?(
               lv,
               ~s(#letters-needed-fix[href="/teams/#{team.subdomain}/settings/signer"]),
               "team settings"
             )
    end

    test "a choice that fits none of the checked greys out and says why",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      attend(team, avery)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      check(lv, [avery], "send")

      assert has_element?(lv, ~s(#letters-choice input[value="email"][disabled]))
      assert has_element?(lv, "#letters-choice", "The member checked has a letter to email.")
      assert has_element?(lv, ~s(#letters-choice input[value="publish"][disabled]))
      refute has_element?(lv, ~s(#letters-choice input[value="send"][disabled]))
    end

    test "Email letters emails each checked letter again, by its job",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      blake = member_fixture(team, %{name: "Blake", email: nil})
      for member <- [avery, blake], do: attend(team, member)
      letter = tax_credit_letter_fixture(avery, %{year: 2025, email_status: :sent})
      tax_credit_letter_fixture(blake, %{year: 2025})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      check(lv, [avery, blake], "email")
      assert has_element?(lv, "#letters-apply", "Email 1 letter")

      apply_choice(lv, [avery, blake], "email")

      assert_email_sent(fn email -> assert email.to == [{"", avery.email}] end)
      assert_no_email_sent()
      assert Repo.reload!(letter).email_status == :sent
      assert render(lv) =~ "Emailing 1 letter again."
    end

    test "Publish again prints a new letter for each checked one out of date, and emails it",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      blake = member_fixture(team, %{name: "Blake"})
      for member <- [avery, blake], do: attend(team, member)

      old =
        tax_credit_letter_fixture(avery, %{year: 2025, primary_minutes: 60, secondary_minutes: 0})

      tax_credit_letter_fixture(blake, %{year: 2025, primary_minutes: 90, secondary_minutes: 0})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      check(lv, [avery, blake], "publish")
      assert has_element?(lv, "#letters-apply", "Publish 1 letter again")
      assert has_element?(lv, ~s(#letters-apply[data-confirm-button="Publish again"]))

      apply_choice(lv, [avery, blake], "publish")
      render_async(lv, 10_000)

      assert old |> Repo.reload!() |> PublishedPDF.status() == :replaced
      new = TaxCreditLetter.get_current(avery, 2025)
      assert TaxCreditLetter.minutes(new) == {90, 0}
      assert_email_sent(fn email -> assert email.to == [{"", avery.email}] end)
      assert render(lv) =~ "Published 1 letter again."
      refute has_element?(lv, "#hours-changed-#{avery.id}")
    end

    test "a filter that hides a checked row unchecks it", %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      blake = member_fixture(team, %{name: "Blake"})
      for member <- [avery, blake], do: attend(team, member)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")
      check(lv, [avery, blake], "send")
      assert has_element?(lv, "#letters-apply", "Send 2 letters")

      lv
      |> element("#tax_credit_letter_filter_form")
      |> render_change(%{"form" => %{"q" => "ave"}})

      assert has_element?(lv, "#letters-apply", "Send 1 letter")
    end

    test "never makes a letter for another team's member", %{team: team} do
      other_team = team_fixture()
      outsider = member_fixture(other_team)
      attend(other_team, outsider)

      summary = CreateTaxCreditLetters.call(team, 2025, [outsider.id])

      assert summary.created == 0
      assert Repo.aggregate(PublishedPDF, :count) == 0
    end
  end
end

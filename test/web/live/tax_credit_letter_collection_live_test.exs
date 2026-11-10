defmodule Web.TaxCreditLetterCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.Event
  alias App.Model.PublishedPDF
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

  describe "sending letters to everyone shown" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      %{conn: log_in_user(conn, user), team: team}
    end

    # 90 minutes of primary hours in 2025.
    defp attend(team, member) do
      activity = activity_fixture(team, %{started_at: ~U[2025-03-01 17:00:00Z]})

      attendance_fixture(activity, member, %{
        started_at: ~U[2025-03-01 17:00:00Z],
        finished_at: ~U[2025-03-01 18:30:00Z]
      })
    end

    test "creates and emails a letter for each member with hours and no letter",
         %{conn: conn, team: team} do
      avery = member_fixture(team, %{name: "Avery"})
      blake = member_fixture(team, %{name: "Blake", email: nil})
      casey = member_fixture(team, %{name: "Casey"})
      _no_hours = member_fixture(team, %{name: "Devon"})
      for member <- [avery, blake, casey], do: attend(team, member)
      had = tax_credit_letter_fixture(casey, %{year: 2025})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025&filter=any")

      assert has_element?(lv, "#send-all-button", "Send 2 letters")

      assert has_element?(
               lv,
               ~s(#send-all-button[data-confirm$="No email, so not emailed: Blake."])
             )

      lv |> element("#send-all-button") |> render_click()

      assert has_element?(
               lv,
               "#letters-sent",
               "2 tax credit letters created for 2025. Emailing 1 of them now."
             )

      assert has_element?(lv, "#letters-no-email", "Blake")
      refute has_element?(lv, "#send-all-button")

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

      assert has_element?(lv, "#send-letter-#{avery.id}")
      assert has_element?(lv, "#letter-state-#{blake.id}", "Not emailed")
      assert has_element?(lv, "#letter-no-email-#{blake.id}", "No email")
      assert has_element?(lv, "#letter-state-#{casey.id}", "Emailed")
      refute has_element?(lv, "#send-letter-#{casey.id}")
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

      assert has_element?(lv, "#send-all-button", "Send 11 letters")

      assert has_element?(
               lv,
               ~s(#send-all-button[data-confirm-check="I understand 10 members get this email."])
             )

      assert has_element?(lv, ~s(#send-all-button[data-confirm-list*="not emailed: Member 1."]))
    end

    test "warns that letters go out unsigned until the team has a signature",
         %{conn: conn, team: team} do
      team |> member_fixture() |> then(&attend(team, &1))

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025")
      assert has_element?(lv, "#send-all-unsigned")
      assert has_element?(lv, ~s(#send-all-button[data-confirm$="They go out unsigned."]))

      {:ok, _team} = SaveTeamSignature.call(team, png_fixture(600, 150))

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/tax-credit-letters?year=2025")
      refute has_element?(lv, "#send-all-unsigned")
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

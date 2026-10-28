defmodule Web.MeLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
  alias App.Model.MemberCard
  alias App.Operation.SetTeamMemberLogins
  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture()
    test_pid = self()

    # The page reads nothing from D4H; a read would show here.
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      send(test_pid, {:d4h_read, conn.request_path})
      Req.Test.json(conn, %{})
    end)

    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  # The page, once anything it loads after showing is done, so it can't outlive the test.
  defp open(conn, path) do
    {:ok, lv, _html} = live(conn, path)
    render_async(lv)
    lv
  end

  # An activity the member attended, from `started_at` for `minutes`.
  defp attend(team, member, title, kind, started_at, minutes, tags \\ []) do
    finished_at = DateTime.add(started_at, minutes * 60)

    activity =
      activity_fixture(team, %{
        title: title,
        activity_kind: kind,
        started_at: started_at,
        finished_at: finished_at,
        tags: tags
      })

    attendance_fixture(activity, member, %{
      started_at: started_at,
      finished_at: finished_at,
      duration_in_minutes: minutes
    })
  end

  describe "Your membership" do
    test "is the member's own page in the team's space", %{conn: conn, team: team, member: member} do
      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "h1", member.name)
      assert has_element?(lv, "#nav-area", team.name)
      assert has_element?(lv, "#side-nav-me[aria-current=page]", "Your membership")
      refute has_element?(lv, "#side-nav-groups")

      assert has_element?(
               lv,
               ~s{#member-head-photo[src="/teams/#{team.subdomain}/members/#{member.id}/image"]}
             )
    end

    test "a new member's page explains each part", %{conn: conn, team: team} do
      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#no-activities", "No activities yet")
      refute has_element?(lv, "#year-stats")
      assert has_element?(lv, "#no-qualifications", "No qualifications yet")
      assert has_element?(lv, "#no-milestones", "No milestones yet")
      refute has_element?(lv, "#all-activities")
      assert has_element?(lv, "#no-card")
      refute has_element?(lv, "#letter")
    end

    test "this year's 10 latest, and a link to all of them on this year's page",
         %{conn: conn, team: team, member: member} do
      %{year: year, mid_year: mid_year} = this_year_fixture(team)

      [oldest | _rest] =
        for n <- 1..11 do
          attend(team, member, "Training #{n}", "exercise", DateTime.add(mid_year, n, :second), 1)
        end

      last_year = (year - 1) |> Date.new!(6, 1) |> DateTime.new!(~T[18:00:00], "Etc/UTC")
      attend(team, member, "Last year's search", "incident", last_year, 60)

      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "h2", "Activities")
      assert has_element?(lv, ~s|#year option[value="#{year}"][selected]|)
      assert has_element?(lv, "#activities-list", "Training 11")
      assert has_element?(lv, "#activities-list", "Training 2")
      refute has_element?(lv, "#activities-list-#{oldest.id}")
      refute has_element?(lv, "#activities-list", "Last year's search")

      assert has_element?(
               lv,
               ~s{#all-activities[href="/teams/#{team.subdomain}/me/activities?year=#{year}"]},
               "All 11 activities in #{year}"
             )
    end

    test "a year's total, primary, and secondary hours, counted as the letter counts them",
         %{conn: conn, team: team, member: member} do
      %{year: year} = this_year_fixture(team)
      june = (year - 1) |> Date.new!(6, 1) |> DateTime.new!(~T[18:00:00], "Etc/UTC")

      # A day apart, since the letter counts overlapping time once.
      attend(team, member, "Rope rescue", "exercise", june, 180, ["Primary Hours"])

      attend(team, member, "PR booth", "event", DateTime.add(june, 1, :day), 120, [
        "Secondary Hours"
      ])

      attend(team, member, "Board meeting", "event", DateTime.add(june, 2, :day), 240)

      attend(team, member, "Two years ago", "exercise", DateTime.add(june, -365, :day), 600, [
        "Primary Hours"
      ])

      lv = open(conn, ~p"/teams/#{team}/me?year=#{year - 1}")

      assert has_element?(lv, "#stat-total", "5")
      assert has_element?(lv, "#stat-total .label", "Total hours")
      assert has_element?(lv, "#stat-primary", "3")
      assert has_element?(lv, "#stat-secondary", "2")
      refute has_element?(lv, "#stat-incidents")
      assert has_element?(lv, "#activities-list", "Board meeting")
      refute has_element?(lv, "#activities-list", "Two years ago")
      assert has_element?(lv, "#all-activities", "All 3 activities in #{year - 1}")
    end

    test "the year menu picks the year, and a year with nothing says so",
         %{conn: conn, team: team, member: member} do
      %{year: year} = this_year_fixture(team)
      last_year = (year - 1) |> Date.new!(6, 1) |> DateTime.new!(~T[18:00:00], "Etc/UTC")
      attend(team, member, "Last year's search", "incident", last_year, 60)

      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#no-activities-in-year", "No activities in #{year}")
      refute has_element?(lv, "#no-activities")
      refute has_element?(lv, "#year-stats")

      lv |> form("#years", %{year: year - 1}) |> render_change()

      assert_patch(lv, ~p"/teams/#{team}/me?year=#{year - 1}")
      assert has_element?(lv, "#activities-list", "Last year's search")
      refute has_element?(lv, "#no-activities-in-year")
    end

    test "a year with no attendance, or not a year, is a 404", %{conn: conn, team: team} do
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/me?year=1999") end
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/me?year=x") end
    end

    test "the 5 latest chores, a New chore link, a link to the rest, and deleting a declined one",
         %{conn: conn, team: team, member: member} do
      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#no-chores")
      assert has_element?(lv, ~s{#chore-log[href="/teams/#{team.subdomain}/me/chores/new"]})

      category = chore_category_fixture(team)
      today = Service.Period.today(DateTime.utc_now(), team.timezone)

      chores =
        for days <- 1..5, do: chore_fixture(member, category, %{date: Date.add(today, -days)})

      declined =
        chore_fixture(member, category, %{
          status: :declined,
          date: today,
          description: "Slept at the hall",
          decline_reason: "Not a chore.",
          decided_at: DateTime.utc_now()
        })

      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#chores-list-#{declined.id}", "Slept at the hall")
      assert has_element?(lv, "#chores-list-#{declined.id} .badge", "Declined")
      assert has_element?(lv, "#chores-list-#{declined.id}", "Not a chore.")
      refute has_element?(lv, "#chore-delete-#{hd(chores).id}")
      assert has_element?(lv, "#chores-list-#{hd(chores).id}")
      refute has_element?(lv, "#chores-list-#{List.last(chores).id}")
      assert has_element?(lv, ".action #all-chores")

      lv |> element("#chore-delete-#{declined.id}") |> render_click()
      refute has_element?(lv, "#chores-list-#{declined.id}")
      assert has_element?(lv, "#chores-list-#{List.last(chores).id}")
    end

    test "qualifications soonest first, with the days left on one expiring soon and none with no end",
         %{conn: conn, team: team, member: member} do
      first_aid = qualification_fixture(team, %{title: "First Aid"})
      ends_at = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
      qualification_award_fixture(first_aid, member, %{ends_at: ends_at})
      organization_fixture([team], %{short_name: "BCSARA"})
      ics = qualification_fixture(team, %{title: "ICS 100", organization_owned: true})
      qualification_award_fixture(ics, member, %{ends_at: nil})

      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#qualifications-list-#{first_aid.id} .badge", "30 days")
      refute has_element?(lv, "#qualifications-list-#{first_aid.id}", "BCSARA")

      # No end is a blank cell. The organization's qualification names it (#652).
      assert has_element?(lv, "#qualifications-list-#{ics.id}", "ICS 100 · BCSARA")
      refute has_element?(lv, "#qualifications-list", "Does not expire")
    end

    test "the ID card, with Wallet buttons and the verify link",
         %{conn: conn, team: team, member: member} do
      App.ApplePassCredentials.configure()
      team = team |> Ecto.Changeset.change(id_cards_enabled: true) |> Repo.update!()

      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#no-card", "Ask one for yours")

      card = member_card_fixture(member)
      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#id-card", "a current member of #{team.name}")
      assert has_element?(lv, "#card-verify-link", MemberCard.format_code(card.code))

      assert has_element?(
               lv,
               ~s{#apple-pass[href="/teams/#{team.subdomain}/me/card/apple-wallet"]}
             )
    end

    test "the latest tax credit letter, to download", %{conn: conn, team: team, member: member} do
      tax_credit_letter_fixture(member, %{year: 2024})

      letter =
        tax_credit_letter_fixture(member, %{
          year: 2025,
          primary_minutes: 147 * 60,
          secondary_minutes: 25 * 60
        })

      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#letter h2", "2025 tax credit letter")
      # Its hours are on the year page, so they aren't read as the last 12 months'.
      refute has_element?(lv, "#letter dd")

      assert has_element?(
               lv,
               ~s{#letter-download[href="/teams/#{team.subdomain}/me/tax-credit-letters/#{letter.id}/pdf"]}
             )
    end

    test "contact details, with the emergency contact from the copy, so the page never reads D4H",
         %{conn: conn, team: team, member: member} do
      member
      |> Ecto.Changeset.change(
        phone: "6045550188",
        address: "2140 Fern Street",
        primary_emergency_contact: %{
          "name" => "Sam Rivera",
          "relation" => "Partner",
          "primary_phone" => "6045550100",
          "secondary_phone" => "604-555-0101"
        }
      )
      |> Repo.update!()

      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#contact-mobile", "604-555-0188")
      assert has_element?(lv, "#contact-address", "2140 Fern Street")
      assert has_element?(lv, "#contact-emergency", "Sam Rivera (Partner)")
      assert has_element?(lv, "#contact-emergency span", "604-555-0100")
      assert has_element?(lv, "#contact-emergency span", "604-555-0101")
      refute has_element?(lv, "#contact-emergency-2")
      refute_received {:d4h_read, _path}
      assert has_element?(lv, ~s{#change-details[href="/teams/#{team.subdomain}/me/details"]})
    end

    test "both emergency contacts, when the second has something to show",
         %{conn: conn, team: team, member: member} do
      member
      |> Ecto.Changeset.change(
        primary_emergency_contact: %{"name" => "Sam Rivera", "primary_phone" => "6045550100"},
        secondary_emergency_contact: %{"name" => "Lee Chan", "relation" => "Sister"}
      )
      |> Repo.update!()

      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#contact-emergency", "Sam Rivera")
      assert has_element?(lv, "#contact-emergency-2", "Lee Chan (Sister)")
    end

    test "every milestone, newest first", %{conn: conn, team: team, member: member} do
      member
      |> Ecto.Changeset.change(
        joined_at:
          DateTime.utc_now() |> DateTime.add(-16 * 366, :day) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      starts = DateTime.utc_now() |> DateTime.add(-30, :day) |> DateTime.truncate(:second)

      incident =
        activity_fixture(team, %{
          title: "Long search",
          activity_kind: "incident",
          started_at: starts
        })

      attendance_fixture(incident, member, %{
        started_at: starts,
        finished_at: DateTime.add(starts, 101 * 3600)
      })

      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#milestones-list-hours-100", "Long search")
      assert has_element?(lv, "#milestones-list-incidents-1", "First incident")
      assert has_element?(lv, "#milestones-list-years-15")
      assert has_element?(lv, "#milestones-list-years-1")

      # The last 30 days' are new; the 15 years came about a year ago.
      assert has_element?(lv, "#milestones-list-hours-100 .badge", "New")
      refute has_element?(lv, "#milestones-list-years-15 .badge")
    end

    test "every item the member holds, with no cap and no links (#490)",
         %{conn: conn, team: team, member: member} do
      items =
        for n <- 1..7,
            do:
              equipment_item_fixture(team, %{
                title: "Kit #{n}",
                member_id: member.id,
                barcode: nil
              })

      old =
        equipment_item_fixture(team, %{title: "Old kit", member_id: member.id, status: "retired"})

      equipment_item_fixture(team_fixture(), %{title: "Stray kit", member_id: member.id})

      lv = open(conn, ~p"/teams/#{team}/me")

      for item <- items,
          do: assert(has_element?(lv, "#equipment-list-#{item.id}", item.title))

      assert has_element?(lv, "#equipment-list-#{hd(items).id}", "Radio")
      refute has_element?(lv, "#equipment-list a")
      assert has_element?(lv, "#equipment-list-#{old.id} .badge", "Retired")
      refute has_element?(lv, "#equipment-list", "Stray kit")
    end

    test "a kit's contents follow it, with the kit they're in", %{
      conn: conn,
      team: team,
      member: member
    } do
      kit = equipment_item_fixture(team, %{title: "First aid kit 6", member_id: member.id})

      pouch =
        equipment_item_fixture(team, %{
          title: "Pouch",
          d4h_container_id: kit.d4h_equipment_id,
          location_title: nil
        })

      equipment_item_fixture(team, %{title: "Zip ties", member_id: member.id})

      lv = open(conn, ~p"/teams/#{team}/me")

      assert has_element?(lv, "#equipment-list-#{pouch.id}", "First aid kit 6")
      assert has_element?(lv, "#equipment-list tr:nth-child(2)#equipment-list-#{pouch.id}")
    end

    test "no Equipment for a member who holds nothing", %{conn: conn, team: team} do
      lv = open(conn, ~p"/teams/#{team}/me")
      refute has_element?(lv, "#equipment")
    end

    test "the member's own photo, or a 404 so the page shows initials",
         %{conn: conn, team: team, member: member} do
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))
      conn = get(conn, ~p"/teams/#{team}/members/#{member}/image")
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "image/png"

      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))
      assert conn |> recycle() |> get(~p"/teams/#{team}/members/#{member}/image") |> response(404)
    end
  end

  describe "who reaches it" do
    test "a member reaches no team admin page", %{conn: conn, team: team, member: member} do
      assert_raise Web.Status.NotFound, fn ->
        live(conn, ~p"/teams/#{team}/members/#{member.id}/standing")
      end

      assert_error_sent 404, fn ->
        get(conn, ~p"/teams/#{team}/tax-credit-letters/0/pdf")
      end
    end

    test "nobody reaches it once the team turns member logins off",
         %{conn: conn, team: team, user: user} do
      {:ok, _team} = SetTeamMemberLogins.call(team, false, user)
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/me") end
    end

    test "a member who left can't reach it", %{conn: conn, team: team, member: member} do
      member |> Ecto.Changeset.change(left_at: ~U[2026-01-01 00:00:00Z]) |> Repo.update!()
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/me") end
    end

    test "a member of another team can't reach it", %{conn: conn} do
      other = member_logins_team_fixture()
      member_fixture(other)
      assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{other}/me") end
    end

    test "a team admin gets their own page, since they're a member too", %{conn: conn} do
      %{user: manager, team: team} = user_with_team_fixture()
      team |> Ecto.Changeset.change(member_logins: true, chores_enabled: true) |> Repo.update!()

      lv = open(log_in_user(conn, manager), ~p"/teams/#{team}/me")
      assert has_element?(lv, "#side-nav-me[aria-current=page]")
      assert has_element?(lv, "#side-nav-groups")
    end

    test "someone not a member there gets a 404, even an admin", %{conn: conn, team: team} do
      %{user: manager} = user_with_team_fixture()
      admin = make_admin(AccountsFixtures.user_fixture())

      for user <- [manager, admin] do
        conn = log_in_user(conn, user)
        assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/me") end
      end
    end

    test "logged out, it asks to log in", %{team: team} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), ~p"/teams/#{team}/me")
    end
  end

  describe "downloads" do
    test "a qualification with a certificate links to it, which opens in the browser",
         %{conn: conn, team: team, member: member} do
      award = certificate_award_fixture(team, member)
      plain = qualification_award_fixture(qualification_fixture(team), member)

      lv = open(conn, ~p"/teams/#{team}/me")
      assert has_element?(lv, "#certificate-#{award.id}", "Certificate")
      refute has_element?(lv, "#certificate-#{plain.id}")

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        assert conn.request_path =~ "/documents/77/download"

        conn
        |> Plug.Conn.put_resp_content_type("application/pdf", nil)
        |> Plug.Conn.send_resp(200, "%PDF-1.7")
      end)

      conn = get(conn, ~p"/teams/#{team}/me/qualifications/#{award.id}/certificate")
      assert response(conn, 200) == "%PDF-1.7"
      assert get_resp_header(conn, "content-type") == ["application/pdf"]

      assert get_resp_header(conn, "content-disposition") == [
               ~s(inline; filename="Standard First Aid.pdf")
             ]

      assert get_resp_header(conn, "content-security-policy") == ["sandbox"]
    end

    test "a certificate that isn't a PDF or an image downloads", %{
      conn: conn,
      team: team,
      member: member
    } do
      award = certificate_award_fixture(team, member)

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<script></script>")
      end)

      conn = get(conn, ~p"/teams/#{team}/me/qualifications/#{award.id}/certificate")
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment;"
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end

    test "another member's certificate, or an award with none, is a 404",
         %{conn: conn, team: team, member: member} do
      theirs = certificate_award_fixture(team, member_fixture(team))
      none = qualification_award_fixture(qualification_fixture(team), member)

      for award <- [theirs, none] do
        assert_error_sent 404, fn ->
          get(conn, ~p"/teams/#{team}/me/qualifications/#{award.id}/certificate")
        end
      end
    end

    test "a certificate D4H won't send is a 404", %{conn: conn, team: team, member: member} do
      award = certificate_award_fixture(team, member)
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))

      conn = get(conn, ~p"/teams/#{team}/me/qualifications/#{award.id}/certificate")
      assert response(conn, 404)
    end

    test "the member's own letter", %{conn: conn, team: team, member: member} do
      letter = tax_credit_letter_fixture(member)
      conn = get(conn, ~p"/teams/#{team}/me/tax-credit-letters/#{letter.id}/pdf")

      assert response(conn, 200)
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/pdf"
    end

    test "another member's letter on the same team is a 404", %{conn: conn, team: team} do
      letter = tax_credit_letter_fixture(member_fixture(team))

      assert_error_sent 404, fn ->
        get(conn, ~p"/teams/#{team}/me/tax-credit-letters/#{letter.id}/pdf")
      end
    end

    test "the member's own Apple Wallet pass", %{conn: conn, team: team, member: member} do
      App.ApplePassCredentials.configure()
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))
      member_card_fixture(member)

      conn = get(conn, ~p"/teams/#{team}/me/card/apple-wallet")

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/vnd.apple.pkpass"
    end

    test "no pass without a card", %{conn: conn, team: team} do
      App.ApplePassCredentials.configure()
      assert conn |> get(~p"/teams/#{team}/me/card/apple-wallet") |> response(404)
    end
  end
end

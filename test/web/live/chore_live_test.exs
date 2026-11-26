defmodule Web.ChoreLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Operation.SaveChore
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    team =
      team
      |> Ecto.Changeset.change(
        member_logins: true,
        chores_enabled: true,
        d4h_access_key: "team-key"
      )
      |> Repo.update!()

    tag_fixture(team, "Primary Hours")
    category = chore_category_fixture(team)
    member = member_fixture(team, %{name: "Sam Rivera"})
    me = Repo.get_by!(App.Model.Member, team_id: team.id, email: user.email)

    %{
      conn: log_in_user(conn, user),
      user: user,
      team: team,
      member: member,
      me: me,
      category: category
    }
  end

  # D4H answering every write: event 900, and attendance row 701 for `member`. `fail`
  # answers a new event with a 500.
  defp stub_d4h(member, fail \\ false) do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      cond do
        fail and conn.method == "POST" and conn.request_path =~ ~r{/events$} ->
          conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"title" => "D4H is down"})

        conn.request_path =~ "/attendance" and conn.method == "GET" ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        conn.request_path =~ "/attendance" ->
          Req.Test.json(conn, %{
            "id" => 701,
            "activity" => %{"resourceType" => "Event", "id" => 900},
            "member" => %{"resourceType" => "Member", "id" => member.d4h_member_id},
            "status" => "ATTENDING",
            "startsAt" => "2026-10-06T07:00:00Z",
            "endsAt" => "2026-10-06T08:30:00Z"
          })

        true ->
          Req.Test.json(conn, %{
            "id" => 900,
            "resourceType" => "Event",
            "owner" => %{"resourceType" => "Team", "id" => 1},
            "published" => false,
            "startsAt" => "2026-10-06T07:00:00Z",
            "endsAt" => "2026-10-06T08:30:00Z",
            "tags" => []
          })
      end
    end)
  end

  test "the page needs member logins", %{conn: conn, team: team} do
    team = team |> Ecto.Changeset.change(member_logins: false) |> Repo.update!()
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/chores") end
  end

  test "accepting the selected chores sends them to their month's activity; a cleared one stays waiting",
       ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    one = chore_fixture(member, category, %{date: ~D[2026-10-06], minutes: 60})
    two = chore_fixture(member, category, %{date: ~D[2026-10-19], description: "Truck 2 wash"})
    left = chore_fixture(member, category, %{description: "Hall floors"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    refute has_element?(lv, "#side-nav-chores .badge")
    assert has_element?(lv, "#chores-view-waiting[aria-current=page]", "3")
    assert has_element?(lv, "#accept", "Accept 3 chores")

    ids = [to_string(one.id), to_string(two.id)]
    lv |> form("#accept-form", %{chore_ids: ids}) |> render_change()
    assert has_element?(lv, "#accept", "Accept 2 chores")

    stub_d4h(member)
    html = lv |> form("#accept-form", %{chore_ids: ids}) |> render_submit()
    assert html =~ "Accepted 2 chores."
    assert html =~ "Chore activities are up to date."

    assert has_element?(lv, "#waiting-chores #chore-#{left.id}")
    refute has_element?(lv, "#waiting-chores #chore-#{one.id}")
    assert %{status: :accepted, decided_at: %DateTime{}} = Repo.get!(Chore, one.id)
    assert Repo.get!(Chore, left.id).status == :waiting

    [event] = Repo.all(ChoreEvent)
    assert %{month: ~D[2026-10-01], d4h_activity_id: 900, needs_send: false} = event
    refute has_element?(lv, "#chores-to-send")

    lv |> element("#chores-view-accepted", "2") |> render_click()
    assert_patch(lv, ~p"/teams/#{team}/chores?view=accepted")
    assert has_element?(lv, "#chore-event-#{event.id}", "October 2026")
    assert has_element?(lv, "#chore-event-#{event.id}", "2 hours")

    assert has_element?(
             lv,
             ~s(#chore-event-#{event.id} #chore-#{two.id} a[href="/teams/#{team.subdomain}/chores/#{two.id}"]),
             "Truck 2 wash"
           )
  end

  test "a send that does not go through offers Send changes, which sends again", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category, %{date: ~D[2026-10-06]})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")

    stub_d4h(member, true)
    html = lv |> form("#accept-form", %{chore_ids: [to_string(chore.id)]}) |> render_submit()
    assert html =~ "Accepted 1 chore."
    assert html =~ "1 activity did not go through."
    assert has_element?(lv, "#chores-to-send", "1 activity is out of date.")

    assert has_element?(lv, "#send-changes[data-confirm^='Send changes to 1 activity?']")
    stub_d4h(member)
    html = lv |> element("#send-changes") |> render_click()
    assert html =~ "Chore activities are up to date."
    refute has_element?(lv, "#chores-to-send")
    assert [%{needs_send: false, d4h_activity_id: 900}] = Repo.all(ChoreEvent)
  end

  test "a team admin declines a chore with a reason", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}")
    assert has_element?(lv, "#chore-details", "Sam Rivera")

    html = lv |> form("#decline-form", decline: %{reason: ""}) |> render_submit()
    assert html =~ "Enter why, for the member"
    assert Repo.get!(Chore, chore.id).status == :waiting

    {:ok, _lv, html} =
      lv
      |> form("#decline-form", decline: %{reason: "The rental group cleans the hall."})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Declined Truck 1 wash."
    assert html =~ "The rental group cleans the hall."
    assert html =~ ~s(id="chore-#{chore.id}")

    assert %{status: :declined, decline_reason: "The rental group cleans the hall."} =
             Repo.get!(Chore, chore.id)
  end

  test "declining a sent chore takes it off its activity in D4H", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category, %{date: ~D[2026-10-06]})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    stub_d4h(member)
    lv |> form("#accept-form", %{chore_ids: [to_string(chore.id)]}) |> render_submit()

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}")

    {:ok, _lv, html} =
      lv
      |> form("#decline-form", decline: %{reason: "Standby is an activity."})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Declined Truck 1 wash."

    assert html =~ "Chore activities are up to date."
    assert %{status: :declined, chore_event_id: nil} = Repo.get!(Chore, chore.id)
  end

  test "a team admin changes an accepted chore to any date", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category, %{status: :accepted})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}/edit")

    stub_d4h(member)

    {:ok, lv, html} =
      lv
      |> form("#chore-form", chore: %{date: "2025-01-15", time: "2h"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/chores?view=accepted")

    assert html =~ "Saved Truck 1 wash."

    assert html =~ "Chore activities are up to date."
    assert has_element?(lv, "#chore-#{chore.id}", "2 hours")
    assert %{status: :accepted, date: ~D[2025-01-15], minutes: 120} = Repo.get!(Chore, chore.id)
    assert [%{month: ~D[2025-01-01]}] = Repo.all(ChoreEvent)
  end

  test "a sent chore's page links its activity", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    activity = activity_fixture(team, %{title: "Chores: Equipment maintenance, October 2026"})

    event =
      Repo.insert!(%ChoreEvent{
        team_id: team.id,
        chore_category_id: category.id,
        month: ~D[2026-10-01],
        d4h_activity_id: activity.d4h_activity_id
      })

    chore = chore_fixture(member, category, %{status: :accepted, chore_event_id: event.id})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}")
    assert has_element?(lv, "#chore-activity a", "Chores: Equipment maintenance, October 2026")
    assert has_element?(lv, "#chore-actions #chore-change")
    refute has_element?(lv, "#accept-form")
    assert has_element?(lv, "#decline-form")
  end

  test "an unknown view is not found", %{conn: conn, team: team} do
    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/chores?view=everything")
    end
  end

  test "declined chores list with why", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx

    chore =
      chore_fixture(member, category, %{
        status: :declined,
        decided_at: ~U[2026-10-20 18:00:00.000000Z],
        decline_reason: "Standby is an activity."
      })

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?view=declined")
    assert has_element?(lv, "#chores-view-declined[aria-current=page]", "1")
    assert has_element?(lv, "#declined-chores #chore-#{chore.id}", "Standby is an activity.")
  end

  test "a decided chore names the team admin who decided it", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    named = App.AccountsFixtures.user_fixture()
    manager_fixture(team, %{email: named.email, name: "Avery Chen"})
    unnamed = App.AccountsFixtures.user_fixture()

    decided = fn user ->
      chore_fixture(member, category, %{
        status: :accepted,
        decided_at: ~U[2026-10-20 18:00:00.000000Z],
        decided_by_user_id: user.id
      })
    end

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{decided.(named).id}")
    assert has_element?(lv, "#chore-status", "Avery Chen")
    refute has_element?(lv, "#chore-status", named.email)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{decided.(unnamed).id}")
    assert has_element?(lv, "#chore-status", unnamed.email)
  end

  # Another team admin should accept a team admin's chores (#697).
  test "a team admin's own chores say You, start cleared, and take a box to accept", ctx do
    %{conn: conn, team: team, member: member, me: me, category: category} = ctx
    theirs = chore_fixture(member, category, %{date: ~D[2026-10-06]})
    mine = chore_fixture(me, category, %{date: ~D[2026-10-06], description: "Grant report"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#chore-#{mine.id}-member-you.badge-primary", "You")
    refute has_element?(lv, "#chore-#{theirs.id}-member-you")
    assert has_element?(lv, "#chores-view-yours", "Yours")
    assert has_element?(lv, "#waiting-chores-select-#{theirs.id}[checked]")
    refute has_element?(lv, "#waiting-chores-select-#{mine.id}[checked]")
    assert has_element?(lv, ~s{#waiting-chores-select-#{mine.id}[data-select-all="skip"]})
    assert has_element?(lv, "#accept", "Accept 1 chore")
    refute has_element?(lv, "#accept-own")

    ids = [to_string(theirs.id), to_string(mine.id)]
    lv |> form("#accept-form", %{chore_ids: ids}) |> render_change()
    assert has_element?(lv, "#accept-own")
    assert has_element?(lv, "#accept[disabled]", "Accept 2 chores")

    # A stale page or a second tab doesn't get past the box.
    html = render_submit(lv, "accept", %{chore_ids: ids})
    assert html =~ "Select Accept my own chores to accept yours."
    assert Repo.get!(Chore, mine.id).status == :waiting
    assert Repo.get!(Chore, theirs.id).status == :waiting

    lv |> form("#accept-form", %{chore_ids: ids, own: "true"}) |> render_change()
    refute has_element?(lv, "#accept[disabled]")

    stub_d4h(member)
    lv |> form("#accept-form", %{chore_ids: ids, own: "true"}) |> render_submit()
    assert Repo.get!(Chore, mine.id).status == :accepted
    assert Repo.get!(Chore, theirs.id).status == :accepted
  end

  test "a team admin's own chore's page takes the box to accept it; declining doesn't", ctx do
    %{conn: conn, team: team, member: member, me: me, category: category} = ctx
    theirs = chore_fixture(member, category)
    mine = chore_fixture(me, category, %{date: ~D[2026-10-06]})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{theirs.id}")
    refute has_element?(lv, "#accept-own")
    refute has_element?(lv, "#chore-accept[disabled]")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{mine.id}")
    assert has_element?(lv, "#accept-own")
    assert has_element?(lv, "#chore-accept[disabled]")
    assert has_element?(lv, "#chore-decline-button")

    assert render_submit(lv, "accept", %{}) =~ "Select Accept my own chores to accept yours."
    assert Repo.get!(Chore, mine.id).status == :waiting

    lv |> form("#accept-form", %{own: "true"}) |> render_change()
    refute has_element?(lv, "#chore-accept[disabled]")

    stub_d4h(me)

    {:ok, _lv, _html} =
      lv |> form("#accept-form", %{own: "true"}) |> render_submit() |> follow_redirect(conn)

    assert Repo.get!(Chore, mine.id).status == :accepted
  end

  test "another team's chore is not found", %{conn: conn, team: team} do
    other_team = team_fixture()
    chore = chore_fixture(member_fixture(other_team), chore_category_fixture(other_team))

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/teams/#{team}/chores/#{chore.id}") end
  end

  # Linda's case (#645): a team admin who is also a member looks under Chores to log one.
  test "a team admin who is a member logs their own chore from Chores", ctx do
    %{conn: conn, team: team, category: category} = ctx
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#chores-view-yours")
    assert has_element?(lv, ~s{#chore-log[href="/teams/#{team.subdomain}/chores/new"]})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    today = Service.Period.today(DateTime.utc_now(), team.timezone)

    {:ok, lv, _html} =
      lv
      |> form("#chore-form",
        chore: %{
          date: Date.to_iso8601(today),
          time: "30m",
          chore_category_id: category.id,
          description: "Grant report"
        }
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/chores?view=yours")

    [chore] = Repo.all(Chore)
    assert chore.status == :waiting
    assert has_element?(lv, "#chore-#{chore.id}", "Grant report")
    assert has_element?(lv, "#chores-view-yours[aria-current]")
  end

  test "a SAR Duty admin who isn't on the team gets no Yours and no Log a chore", ctx do
    %{conn: conn, team: team} = ctx
    admin = App.AccountsFixtures.user_fixture() |> make_admin()
    conn = log_in_user(conn, admin)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#chores-view-waiting")
    refute has_element?(lv, "#chores-view-yours")
    refute has_element?(lv, "#chore-log")
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/chores/new") end
  end

  describe "chores logged together" do
    setup %{me: me, team: team} do
      me = me |> Ecto.Changeset.change(name: "Alex Chen") |> Repo.update!()

      others =
        for name <- ~w(Blake Cameron Dana Eli Riley Zoe),
            do: member_fixture(team, %{name: "#{name} #{name}son"})

      %{me: me, others: others}
    end

    defp log_together(logger, members, category, attrs \\ %{}) do
      together = %{logged_together_id: Ecto.UUID.generate(), logged_by_member_id: logger.id}

      members
      |> Enum.map(&chore_fixture(&1, category, Map.merge(together, attrs)))
      |> Enum.sort_by(&Repo.get!(App.Model.Member, &1.member_id).name)
    end

    # D4H answering every write, each attendance row its member's.
    defp stub_d4h_echo do
      Req.Test.stub(App.Adapter.D4H, fn conn ->
        cond do
          conn.request_path =~ "/attendance" and conn.method == "GET" ->
            Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

          conn.request_path =~ "/attendance" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            member_id = body |> Jason.decode!() |> Map.get("memberId")

            Req.Test.json(conn, %{
              "id" => System.unique_integer([:positive]),
              "activity" => %{"resourceType" => "Event", "id" => 900},
              "member" => %{"resourceType" => "Member", "id" => member_id},
              "status" => "ATTENDING",
              "startsAt" => "2026-10-06T07:00:00Z",
              "endsAt" => "2026-10-06T08:30:00Z"
            })

          true ->
            Req.Test.json(conn, %{
              "id" => 900,
              "resourceType" => "Event",
              "owner" => %{"resourceType" => "Team", "id" => 1},
              "published" => false,
              "startsAt" => "2026-10-06T07:00:00Z",
              "endsAt" => "2026-10-06T08:30:00Z",
              "tags" => []
            })
        end
      end)
    end

    test "a gear day for 8 is one row, the team admin's own, accepted together", ctx do
      %{conn: conn, team: team, me: me, member: sam, others: others, category: category} = ctx

      gear =
        log_together(me, [me, sam | others], category, %{minutes: 180, description: "Gear day"})

      [first | _rest] = gear
      assert first.member_id == me.id
      single = chore_fixture(sam, category, %{description: "Hall floors"})
      left = chore_fixture(sam, category, %{description: "Radio check"})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
      assert has_element?(lv, "#chores-view-waiting", "10")
      for chore <- tl(gear), do: refute(has_element?(lv, "#waiting-chores #chore-#{chore.id}"))

      row = lv |> element("#waiting-chores #chore-#{first.id}") |> render()
      names = ["Alex Chen", "Blake Blakeson", "Cameron Cameronson", "Sam Rivera", "Zoe Zoeson"]
      positions = Enum.map(names, &(row |> :binary.match(&1) |> elem(0)))
      assert positions == Enum.sort(positions)
      assert has_element?(lv, "#chore-#{first.id}-member-you", "You")
      refute has_element?(lv, "#chore-#{List.last(gear).id}-member-you")
      assert has_element?(lv, "#chore-#{first.id}-each", "3 hours each")
      assert row =~ "24 hours"

      refute has_element?(lv, "#waiting-chores-select-#{first.id}[checked]")
      assert has_element?(lv, ~s{#waiting-chores-select-#{first.id}[data-select-all="skip"]})
      assert has_element?(lv, "#accept", "Accept 2 chores")

      assert render(lv) =~
               "Uncheck a chore to leave it waiting. Open a chore to change or decline it."

      lv |> form("#accept-form", %{chore_ids: ["#{single.id}"]}) |> render_change()
      assert has_element?(lv, "#accept", "Accept 1 chore")

      ids = Enum.map([first, single, left], &"#{&1.id}")
      lv |> form("#accept-form", %{chore_ids: ids}) |> render_change()
      assert has_element?(lv, "#accept[disabled]", "Accept 10 chores")

      assert has_element?(
               lv,
               "#accept-form",
               "I know another team admin should accept the chores I did."
             )

      stub_d4h_echo()
      html = lv |> form("#accept-form", %{chore_ids: ids, own: "true"}) |> render_submit()
      assert html =~ "Accepted 10 chores."

      for chore <- Repo.all(Chore) do
        assert %{status: :accepted, chore_event_id: event_id} = chore
        assert event_id
      end
    end

    test "checking a single chore's row accepts it alone", ctx do
      %{conn: conn, team: team, member: sam, category: category} = ctx
      one = chore_fixture(sam, category)
      other = chore_fixture(sam, category, %{description: "Radio check"})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
      stub_d4h(sam)
      lv |> form("#accept-form", %{chore_ids: ["#{one.id}"]}) |> render_submit()
      assert Repo.get!(Chore, one.id).status == :accepted
      assert Repo.get!(Chore, other.id).status == :waiting
    end

    test "accept/5 takes a row by one of its ids, and needs own: true for the team admin's own",
         ctx do
      %{team: team, me: me, user: user, member: sam, others: others, category: category} = ctx
      now = DateTime.utc_now()
      mine = log_together(me, [me | others], category)
      theirs = log_together(me, [sam | Enum.take(others, 2)], category)

      assert SaveChore.accept(team, [List.last(mine).id], user, now, member: me) == {:error, :own}
      assert Enum.all?(mine, &(Repo.get!(Chore, &1.id).status == :waiting))

      [other_admin] = Enum.take(others, -1)

      assert {:ok, 3} =
               SaveChore.accept(team, [List.last(theirs).id], user, now, member: other_admin)

      assert Enum.all?(theirs, &(Repo.get!(Chore, &1.id).status == :accepted))

      assert {:ok, 7} = SaveChore.accept(team, [hd(mine).id], user, now, member: me, own: true)
    end

    test "a row whose first chore was declined since the page loaded still accepts the rest",
         ctx do
      %{conn: conn, team: team, me: me, member: sam, others: others, category: category} = ctx
      [first | rest] = log_together(me, [sam | others], category)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
      assert has_element?(lv, "#waiting-chores-select-#{first.id}[checked]")
      first |> Ecto.Changeset.change(status: :declined) |> Repo.update!()

      stub_d4h_echo()
      html = lv |> form("#accept-form", %{chore_ids: ["#{first.id}"]}) |> render_submit()
      assert html =~ "Accepted 6 chores."
      assert Enum.all?(rest, &(Repo.get!(Chore, &1.id).status == :accepted))
      assert Repo.get!(Chore, first.id).status == :declined
    end

    test "a row whose first chore was deleted since the page loaded still accepts the rest",
         ctx do
      %{conn: conn, team: team, me: me, member: sam, others: others, category: category} = ctx
      [first | rest] = log_together(me, [sam | others], category)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
      Repo.delete!(first)

      stub_d4h_echo()
      html = lv |> form("#accept-form", %{chore_ids: ["#{first.id}"]}) |> render_submit()
      assert html =~ "Accepted 6 chores."
      assert Enum.all?(rest, &(Repo.get!(Chore, &1.id).status == :accepted))
    end

    test "chores a team admin logged only for others aren't theirs: checked, and no box", ctx do
      %{conn: conn, team: team, me: me, member: sam, others: [cameron | _], category: category} =
        ctx

      [one, _two] = log_together(me, [sam, cameron], category)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
      assert has_element?(lv, "#waiting-chores-select-#{one.id}[checked]")
      refute has_element?(lv, "#waiting-chores-select-#{one.id}[data-select-all]")
      assert has_element?(lv, "#accept", "Accept 2 chores")

      stub_d4h_echo()
      lv |> form("#accept-form", %{chore_ids: ["#{one.id}"]}) |> render_submit()
      assert Chore |> Repo.all() |> Enum.all?(&(&1.status == :accepted))
    end

    test "a changed or declined chore stays in its row, which keeps the box", ctx do
      %{conn: conn, team: team, me: me, member: sam, others: others, category: category} = ctx
      [mine | _rest] = gear = log_together(me, [me, sam | others], category, %{minutes: 180})
      riley = Enum.find(gear, &(&1.member_id == Enum.at(others, 4).id))
      stub_d4h(sam)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{riley.id}/edit")
      lv |> form("#chore-form", chore: %{time: "2h"}) |> render_submit()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
      refute has_element?(lv, "#waiting-chores #chore-#{riley.id}")
      refute has_element?(lv, "#chore-#{mine.id}-each")
      assert has_element?(lv, "#waiting-chores #chore-#{mine.id}", "23 hours")
      assert has_element?(lv, "#waiting-chores #chore-#{mine.id}", "Riley Rileyson: 2 hours")

      sam_chore = Enum.find(gear, &(&1.member_id == sam.id))
      {:ok, page, _html} = live(conn, ~p"/teams/#{team}/chores/#{sam_chore.id}")

      page
      |> form("#decline-form", decline: %{reason: "Not that day"})
      |> render_submit()

      {:ok, page, _html} = live(conn, ~p"/teams/#{team}/chores/#{mine.id}")
      page |> form("#decline-form", decline: %{reason: "Mine"}) |> render_submit()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
      [first | _rest] = gear |> Enum.reject(&(&1.id in [mine.id, sam_chore.id]))
      row = lv |> element("#waiting-chores #chore-#{first.id}") |> render()
      refute row =~ "Alex Chen"
      refute row =~ "Sam Rivera"
      refute row =~ ">You<"
      refute has_element?(lv, "#waiting-chores-select-#{first.id}[checked]")
      assert has_element?(lv, "#accept", "Accept 0 chores")

      lv |> element("#chores-view-yours") |> render_click()
      assert has_element?(lv, "#chore-#{mine.id}", "Declined")
      refute has_element?(lv, "#chore-delete-#{mine.id}")

      assert render_click(lv, "delete", %{"id" => "#{mine.id}"}) =~
               "while a chore logged with it waits"

      assert Repo.get(Chore, mine.id)

      stub_d4h_echo()
      SaveChore.accept(team, [first.id], ctx.user, DateTime.utc_now(), member: me, own: true)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?view=yours")
      lv |> element("#chore-delete-#{mine.id}") |> render_click()
      refute Repo.get(Chore, mine.id)
    end

    test "a chore's page says who logged it and lists the others on it", ctx do
      %{conn: conn, team: team, me: me, member: sam, others: [cameron | _], category: category} =
        ctx

      [alex, cam, _sam] = log_together(me, [me, sam, cameron], category)
      cam |> Ecto.Changeset.change(status: :declined) |> Repo.update!()

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{cam.id}")
      assert has_element?(lv, "#chore-logged", ", by Alex Chen")
      refute has_element?(lv, "#chore-other-#{cam.id}")

      assert has_element?(
               lv,
               ~s{#chore-other-#{alex.id} a[href="/teams/#{team.subdomain}/chores/#{alex.id}"]},
               "Alex Chen"
             )

      assert has_element?(lv, "#chore-other-#{alex.id}", "Waiting")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{alex.id}")
      refute has_element?(lv, "#chore-logged", "by")
      assert has_element?(lv, "#chore-other-#{cam.id}", "Declined")

      alone = chore_fixture(sam, category, %{logged_by_member_id: sam.id})
      old = chore_fixture(sam, category)

      for chore <- [alone, old] do
        {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}")
        refute has_element?(lv, "#chore-logged", "by")
        refute has_element?(lv, "#chore-others")
      end
    end

    test "a member's chore logged with the team admin's takes the box, and accepts alone", ctx do
      %{conn: conn, team: team, me: me, others: [cameron | _], category: category} = ctx
      [alex, cam] = log_together(cameron, [me, cameron], category)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{cam.id}")
      assert has_element?(lv, "#accept-own")
      assert has_element?(lv, "#chore-accept[disabled]")
      assert render_submit(lv, "accept", %{}) =~ "Select Accept my own chores to accept yours."
      assert Repo.get!(Chore, cam.id).status == :waiting

      stub_d4h_echo()

      {:ok, _lv, _html} =
        lv |> form("#accept-form", %{own: "true"}) |> render_submit() |> follow_redirect(conn)

      assert Repo.get!(Chore, cam.id).status == :accepted
      assert Repo.get!(Chore, alex.id).status == :waiting
    end

    test "the team home's count leaves out chores logged with the team admin's", ctx do
      %{conn: conn, team: team, me: me, member: sam, others: [cameron | _], category: category} =
        ctx

      manager_fixture(team)
      log_together(me, [me, cameron], category)
      chore_fixture(sam, category)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
      assert has_element?(lv, "#attention-chores", "1 chore to accept")
    end
  end
end

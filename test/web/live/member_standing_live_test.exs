defmodule Web.MemberStandingLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSetRow
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCheckIn
  alias App.Model.MemberStandingChange
  alias App.Model.NoShow
  alias App.Operation.AddAwayPeriod
  alias App.Operation.DeleteAwayPeriod
  alias App.Operation.DeleteCheckIn
  alias App.Operation.EndAwayPeriod
  alias App.Operation.RecordCheckIn
  alias App.Operation.SetGroupMembers
  alias App.RecordsStub
  alias App.Repo

  defp today(team), do: Service.Period.today(DateTime.utc_now(), team.timezone)
  defp day(team, days_from_today), do: team |> today() |> Date.add(days_from_today)

  test "a member with no away period is active, and the header shows no badge", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    assert has_element?(lv, "#standing-now", "Active")
    refute has_element?(lv, "#member-head-standing")
    assert has_element?(lv, "#no-away-periods")
  end

  test "adding an away period makes the member away, and the history records it",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    ends_on = day(team, 30)

    conn = log_in_user(conn, user)
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/standing")
    refute has_element?(tab, "#away-form")

    # Its own page, from the tab (#1053), and back.
    {:ok, page, _html} = tab |> element("#add-away") |> render_click() |> follow_redirect(conn)
    assert has_element?(page, "h1", "Add an away period for #{member.name}")

    {:ok, lv, html} =
      page
      |> form("#away-form",
        away: %{
          starts_on: today(team),
          ends_on: ends_on,
          reason: "  Parental leave  "
        }
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/members/#{member.id}/standing")

    assert html =~ "Away period added."

    assert has_element?(
             lv,
             "#standing-now",
             "Away until #{Service.Format.date_long(ends_on)} (Parental leave)"
           )

    assert has_element?(lv, "#away-period-list", "Parental leave")

    assert has_element?(
             lv,
             "#member-head-standing.badge-warning",
             "Away until #{Service.Format.date_short(ends_on)}"
           )

    assert [%MemberStandingChange{action: :away_added, user_id: user_id}] =
             Repo.all(MemberStandingChange)

    assert user_id == user.id

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/history")

    assert has_element?(lv, "#member-history", "Away period added: Parental leave")
  end

  test "an away period needs a short reason", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing/away/new")

    away = %{starts_on: today(team), ends_on: day(team, 30)}

    html = lv |> form("#away-form", away: Map.put(away, :reason, "")) |> render_submit()
    assert html =~ "Enter a reason, such as Parental leave."

    html =
      lv
      |> form("#away-form", away: Map.put(away, :reason, String.duplicate("a", 61)))
      |> render_submit()

    assert html =~ "Keep the reason under 60 characters."
    assert Repo.all(MemberAwayPeriod) == []
  end

  test "an away period needs a last day on or after the first", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing/away/new")

    html =
      lv
      |> form("#away-form",
        away: %{starts_on: today(team), ends_on: day(team, -1), reason: "leave"}
      )
      |> render_submit()

    assert html =~ "Enter a last day on or after the first."
    assert Repo.all(MemberAwayPeriod) == []
  end

  test "ending a current away period early makes the member active today", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    period = away_period_fixture(member, day(team, -10), day(team, 10))

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    assert has_element?(lv, "#standing-now", "Away until")
    lv |> element("#end-away-#{period.id}") |> render_click()

    assert has_element?(lv, "#standing-now", "Active")
    assert Repo.reload!(period).ends_on == day(team, -1)
    refute has_element?(lv, "#end-away-#{period.id}")
  end

  test "deleting an away period keeps a record in the history", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    period = away_period_fixture(member, today(team), day(team, 10))

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    refute has_element?(lv, "#end-away-#{period.id}")
    lv |> element("#delete-away-#{period.id}") |> render_click()

    assert has_element?(lv, "#standing-now", "Active")
    assert Repo.all(MemberAwayPeriod) == []
    assert [%MemberStandingChange{action: :away_deleted}] = Repo.all(MemberStandingChange)
  end

  test "not a person wins over an away period", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{not_a_person: true})
    away_period_fixture(member, today(team), day(team, 10))

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    assert has_element?(lv, "#standing-now", "Not a person")
  end

  test "a bot's tab is the Standing section alone, and it gets no away period or check-in (#1053)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{name: "Duty pager", not_a_person: true})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    assert has_element?(lv, "#standing", "A bot or a shared account.")
    assert has_element?(lv, "#mark-person[data-confirm*='Mark Duty pager as a person?']")
    assert has_element?(lv, "#mark-retired")
    refute has_element?(lv, "#retire-hint")

    for id <- ~w(away-periods check-ins no-shows not-a-person),
        do: refute(has_element?(lv, "##{id}"))

    params = %{"starts_on" => today(team), "ends_on" => day(team, 10), "reason" => "Leave"}
    assert AddAwayPeriod.call(team, member.id, user, params) == :not_a_person
    assert Repo.all(MemberAwayPeriod) == []

    check_in = %{"checked_in_on" => today(team)}
    assert RecordCheckIn.call(team, member.id, user, check_in) == :not_a_person
    assert Repo.all(MemberCheckIn) == []
  end

  test "a bot's rows still show, without the forms", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    away_period_fixture(member, day(team, -20), day(team, -10))

    {:ok, _check_in} =
      RecordCheckIn.call(team, member.id, user, %{"checked_in_on" => today(team)})

    member |> Ecto.Changeset.change(not_a_person: true) |> Repo.update!()

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    assert has_element?(lv, "#away-period-list")
    assert has_element?(lv, "#check-in-list")
    refute has_element?(lv, "#add-away")
    refute has_element?(lv, "#record-check-in")
    refute has_element?(lv, "#no-shows")
  end

  test "a retired member reads Retired and gets no away period or check-in", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{name: "Robin Tse", left_at: ~U[2025-06-01 19:00:00Z]})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    assert has_element?(lv, "#standing-now", "Retired")
    assert has_element?(lv, "#retired-on", "Robin Tse retired on June 1, 2025.")
    assert has_element?(lv, "#member-head-standing", "Retired")
    refute has_element?(lv, "#add-away")
    assert has_element?(lv, "#check-ins")
    refute has_element?(lv, "#record-check-in")
    assert has_element?(lv, "#mark-rejoined")
    refute has_element?(lv, "#mark-retired")
    refute has_element?(lv, "#mark-retiring")

    params = %{"starts_on" => today(team), "ends_on" => day(team, 10), "reason" => "Leave"}
    assert AddAwayPeriod.call(team, member.id, user, params) == :retired
    assert Repo.all(MemberAwayPeriod) == []

    check_in = %{"checked_in_on" => today(team)}
    assert RecordCheckIn.call(team, member.id, user, check_in) == :retired
    assert Repo.all(MemberCheckIn) == []
  end

  test "a form page left open while the member retired goes back and says so",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{name: "Robin Tse"})
    conn = log_in_user(conn, user)
    standing = ~p"/teams/#{team}/members/#{member.id}/standing"

    {:ok, lv, _html} = live(conn, standing <> "/check-ins/new")
    member |> Ecto.Changeset.change(left_at: ~U[2025-06-01 19:00:00Z]) |> Repo.update!()

    {:ok, _tab, html} =
      lv
      |> form("#check-in-form", check_in: %{checked_in_on: today(team)})
      |> render_submit()
      |> follow_redirect(conn, standing)

    assert html =~ "Robin Tse is retired."
    assert Repo.all(MemberCheckIn) == []
  end

  test "deleting an away period someone else deleted first says so", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    period = away_period_fixture(member, today(team), day(team, 10))

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    {:ok, _period} = DeleteAwayPeriod.call(team, period.id, user)

    assert lv |> element("#delete-away-#{period.id}") |> render_click() =~
             "That away period was deleted already."

    refute has_element?(lv, "#away-period-#{period.id}")
  end

  test "another team's away period cannot be ended or deleted" do
    %{user: user, team: team} = user_with_team_fixture()
    other = member_fixture(team_fixture())
    period = away_period_fixture(other, day(team, -5), day(team, 10))

    assert DeleteAwayPeriod.call(team, period.id, user) == :gone
    assert EndAwayPeriod.call(team, period.id, user) == :gone
    assert Repo.reload(period)
    assert_raise Ecto.NoResultsError, fn -> AddAwayPeriod.call(team, other.id, user, %{}) end
  end

  test "this year's no-shows are counted and listed, with who followed up (#650)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    activity = activity_fixture(team, %{title: "MIT training"})
    no_show = NoShow.record!(activity, member)

    NoShow.set_followed_up(
      team,
      no_show.id,
      {:note, "sick, told the trainer"},
      user,
      DateTime.utc_now()
    )

    team |> activity_fixture() |> NoShow.record!(member_fixture(team))
    year = DateTime.utc_now() |> Service.YearRange.year_in(team.timezone)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    assert has_element?(lv, "#no-show-count", "1 no-show in #{year}.")
    assert has_element?(lv, "#no-show-#{no_show.id}", "MIT training")
    assert has_element?(lv, "#no-show-#{no_show.id}", "sick, told the trainer")
    assert has_element?(lv, "#no-show-#{no_show.id}", "Followed up by #{user.email}")
  end

  test "a check-in lists the day, who recorded it, and what they heard", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    conn = log_in_user(conn, user)
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/standing")
    assert has_element?(tab, "#no-check-ins")

    {:ok, page, _html} =
      tab |> element("#record-check-in") |> render_click() |> follow_redirect(conn)

    assert has_element?(page, "h1", "Record a check-in with #{member.name}")

    {:ok, lv, html} =
      page
      |> form("#check-in-form",
        check_in: %{checked_in_on: day(team, -2), note: "Busy with school, back in January."}
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/members/#{member.id}/standing")

    assert html =~ "Check-in recorded."
    assert [check_in] = Repo.all(MemberCheckIn)
    assert check_in.user_id == user.id
    assert check_in.checked_in_on == day(team, -2)

    assert has_element?(lv, "#check-in-#{check_in.id}", "Busy with school, back in January.")
    assert has_element?(lv, "#check-in-#{check_in.id}", "Recorded by #{user.email}")
  end

  test "a check-in recorded by mistake can be deleted", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    {:ok, check_in} = RecordCheckIn.call(team, member.id, user, %{"checked_in_on" => today(team)})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    lv |> element("#delete-check-in-#{check_in.id}") |> render_click()

    assert Repo.all(MemberCheckIn) == []
    assert has_element?(lv, "#no-check-ins")
  end

  test "a check-in cannot be in the future", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members/#{member.id}/standing/check-ins/new")

    html =
      lv |> form("#check-in-form", check_in: %{checked_in_on: day(team, 1)}) |> render_submit()

    assert html =~ "Enter today or an earlier day."
    assert Repo.all(MemberCheckIn) == []
  end

  test "another team's member cannot be checked in, nor its check-in deleted" do
    %{user: user, team: team} = user_with_team_fixture()
    other_team = team_fixture()
    other = member_fixture(other_team)

    assert_raise Ecto.NoResultsError, fn ->
      RecordCheckIn.call(team, other.id, user, %{"checked_in_on" => today(team)})
    end

    {:ok, check_in} =
      RecordCheckIn.call(other_team, other.id, user, %{"checked_in_on" => today(team)})

    assert DeleteCheckIn.call(team, check_in.id) == :gone
    assert Repo.reload(check_in)
  end

  test "suggests marking a bot, and the buttons mark it not a person and back", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    bot = member_fixture(team, %{name: "Roster Bot", phone: nil, email: nil})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{bot.id}/standing")

    assert has_element?(lv, "#not-a-person h2", "Not a person")
    assert has_element?(lv, "#not-a-person-suggestion")

    assert has_element?(
             lv,
             "#mark-not-a-person[data-confirm*='Mark Roster Bot as not a person?']"
           )

    assert lv |> element("#mark-not-a-person") |> render_click() =~
             "Marked Roster Bot as not a person."

    assert Repo.reload!(bot).not_a_person
    assert has_element?(lv, "#standing-now", "Not a person")
    refute has_element?(lv, "#not-a-person")
    assert [%{action: :not_a_person}] = Repo.all(MemberStandingChange)

    assert lv |> element("#mark-person") |> render_click() =~ "Marked Roster Bot as a person."

    refute Repo.reload!(bot).not_a_person
    assert has_element?(lv, "#mark-not-a-person")
  end

  test "a retired bot is marked as a person at the end of the tab", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    bot = member_fixture(team, %{not_a_person: true, left_at: ~U[2025-06-01 00:00:00Z]})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{bot.id}/standing")

    assert has_element?(lv, "#standing-now", "Retired")
    assert has_element?(lv, "#still-not-a-person", "is marked as not a person.")
    assert has_element?(lv, "#not-a-person #mark-person")
    refute has_element?(lv, "#mark-not-a-person")
  end

  test "does not suggest marking a member with attendance", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{phone: nil, email: nil})
    attendance_fixture(activity_fixture(team), member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    refute has_element?(lv, "#not-a-person-suggestion")
  end

  describe "Retiring (#514)" do
    setup do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "key"}})
      leavers = group_fixture(team, %{title: "Leavers"})

      team =
        team
        |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id)
        |> Repo.update!()

      test = self()

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        send(test, {:d4h, conn.method, conn.request_path})

        case conn.method do
          "POST" ->
            Req.Test.json(conn, %{"id" => 400, "member" => %{"id" => 1}, "group" => %{"id" => 1}})

          _delete ->
            Req.Test.json(conn, %{})
        end
      end)

      %{user: user, team: team, leavers: leavers}
    end

    test "Mark as retiring adds the member to the team's group, and Remove takes them out",
         %{conn: conn, user: user, team: team, leavers: leavers} do
      member = member_fixture(team, %{name: "Avery Chen"})

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

      assert has_element?(lv, "#mark-retiring[data-confirm*='Mark Avery Chen as retiring?']")
      lv |> element("#mark-retiring") |> render_click()

      assert_received {:d4h, "POST", _path}
      assert has_element?(lv, "#standing-now", "Retiring")
      assert has_element?(lv, "#member-head-standing", "Retiring")
      assert has_element?(lv, "#retiring-items", "Avery Chen holds no items.")
      assert has_element?(lv, "#unmark-retiring + #mark-retired")
      assert GroupMember.get_by(group_id: leavers.id, member_id: member.id)

      lv |> element("#unmark-retiring", "Mark as not retiring") |> render_click()

      assert_received {:d4h, "DELETE", _path}
      assert has_element?(lv, "#standing-now", "Active")
      refute GroupMember.get_by(group_id: leavers.id, member_id: member.id)
    end

    test "Mark as retiring refuses the team's only team admin, who would be locked out",
         %{conn: conn, user: user, team: team, leavers: leavers} do
      me = Member.get_by(team_id: team.id, email: user.email)

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{me.id}/standing")

      assert has_element?(lv, "#mark-retiring[data-confirm*='log in to SAR Duty']")

      assert lv |> element("#mark-retiring") |> render_click() =~
               "Make another member a team admin first."

      refute_received {:d4h, _method, _path}
      refute GroupMember.get_by(group_id: leavers.id, member_id: me.id)
    end

    test "the Groups tab and adding from Members refuse the only team admin too",
         %{conn: conn, user: user, team: team, leavers: leavers} do
      me = Member.get_by(team_id: team.id, email: user.email)

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{me.id}/groups")

      assert lv |> form("#add-group-form", group_id: leavers.id) |> render_submit() =~
               "Make another member a team admin first."

      assert SetGroupMembers.call(
               team,
               :add,
               leavers.id,
               [me.id],
               user,
               DateTime.utc_now()
             ) ==
               {:error, "Make another member a team admin first."}

      refute_received {:d4h, _method, _path}
      refute GroupMember.get_by(group_id: leavers.id, member_id: me.id)
    end

    test "a retiring member D4H still lets in gets a banner on every tab",
         %{conn: conn, user: user, team: team, leavers: leavers} do
      editor = member_fixture(team, %{name: "Eve Editor", d4h_permission: 1})
      none = member_fixture(team, %{name: "Nia None", d4h_permission: 4})
      group_member_fixture(leavers, editor)
      group_member_fixture(leavers, none)
      conn = log_in_user(conn, user)

      for tab <- ["standing", "groups"] do
        {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{editor.id}/#{tab}")
        assert has_element?(lv, "#retiring-access", "Eve Editor can still log in to D4H")
        assert has_element?(lv, "#retiring-access", "access is still Editor")
      end

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{none.id}/standing")
      refute has_element?(lv, "#retiring-access")
    end

    test "says how many items a retiring member holds", %{
      conn: conn,
      user: user,
      team: team,
      leavers: leavers
    } do
      member = member_fixture(team, %{name: "Avery Chen"})
      group_member_fixture(leavers, member)
      for _ <- 1..3, do: equipment_item_fixture(team, %{member_id: member.id})

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

      assert has_element?(
               lv,
               "#retiring-items",
               "Avery Chen holds 3 items. Get them back and move them in D4H before you retire them."
             )
    end

    test "no retiring buttons without a Retiring group, or for a member not a person", %{
      conn: conn,
      user: user,
      team: team
    } do
      bot = member_fixture(team, %{not_a_person: true})

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{bot.id}/standing")

      refute has_element?(lv, "#mark-retiring")

      team |> Ecto.Changeset.change(retiring_d4h_group_id: nil) |> Repo.update!()
      member = member_fixture(team)

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

      refute has_element?(lv, "#mark-retiring")
    end
  end

  # D4H's retire and unretire, from the Standing tab on every team (#1053).
  describe "Mark as retired" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "key"}})
      RecordsStub.stub(fn _method, _path, _body -> {200, RecordsStub.member_json(77)} end)
      %{conn: log_in_user(conn, user), user: user, team: team}
    end

    test "retires an active member in D4H in one step", %{conn: conn, team: team} do
      member = member_fixture(team, %{name: "Casey Dhillon"})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/standing")

      assert has_element?(lv, "#retire-hint", "Mark as retired retires them in D4H too.")

      assert has_element?(
               lv,
               "#mark-retired[data-confirm='Mark Casey Dhillon as retired today?']"
             )

      assert lv |> element("#mark-retired") |> render_click() =~
               "Marked Casey Dhillon as retired."

      # The team's own day at 00:00 UTC, as D4H keeps it.
      day = "#{today(team)}T00:00:00Z"
      path = "/members/#{member.d4h_member_id}/retire"
      assert_received {:records, "PATCH", ^path, %{"direction" => "RETIRE", "date" => ^day}}
      assert [%{action: :retire_member, status: :applied}] = Repo.all(ChangeSetRow)

      # Written here at once, with no sync, so the tab says it.
      assert has_element?(lv, "#standing-now", "Retired")
      date = Service.Format.date_long(today(team))
      assert has_element?(lv, "#retired-on", "Casey Dhillon retired on #{date}.")
    end

    test "refuses a member who holds any item, whatever its status, and says why",
         %{conn: conn, team: team} do
      member = member_fixture(team, %{name: "Sam Rivera"})
      equipment_item_fixture(team, %{title: "Radio 2", member_id: member.id, status: "lost"})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/standing")

      html = lv |> element("#mark-retired") |> render_click()
      assert html =~ "Sam Rivera still holds 1 item."
      assert html =~ "Get it back and move it in D4H first."

      refute_received {:records, _method, _path, _body}
      assert Repo.all(ChangeSetRow) == []
    end

    test "refuses the team's only team admin", %{conn: conn, user: user, team: team} do
      me = Member.get_by(team_id: team.id, email: user.email)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{me.id}/standing")

      assert lv |> element("#mark-retired") |> render_click() =~
               "Make another member a team admin first."

      refute_received {:records, _method, _path, _body}
    end

    test "Mark as rejoined sends D4H's undo of a retire", %{conn: conn, team: team} do
      member = member_fixture(team, %{name: "Robin Tse", d4h_status: "RETIRED"})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/standing")

      assert lv |> element("#mark-rejoined") |> render_click() =~ "Marked Robin Tse as rejoined."

      path = "/members/#{member.d4h_member_id}/retire"
      assert_received {:records, "PATCH", ^path, %{"direction" => "UNRETIRE"}}
      assert has_element?(lv, "#standing-now", "Active")
    end

    test "a SAR Duty Records team retires the same way", %{conn: conn} do
      %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
      member = member_fixture(team)

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

      assert has_element?(lv, "#retire-hint", "retires them in SAR Duty Records too.")
      lv |> element("#mark-retired") |> render_click()

      path = "/members/#{member.d4h_member_id}/retire"
      assert_received {:records, "PATCH", ^path, %{"direction" => "RETIRE"}}
    end
  end
end

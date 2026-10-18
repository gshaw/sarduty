defmodule Web.MemberStandingLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCheckIn
  alias App.Model.MemberStandingChange
  alias App.Operation.AddAwayPeriod
  alias App.Operation.DeleteAwayPeriod
  alias App.Operation.DeleteCheckIn
  alias App.Operation.EndAwayPeriod
  alias App.Operation.RecordCheckIn
  alias App.Repo

  defp today(team), do: Service.Period.today(DateTime.utc_now(), team.timezone)
  defp day(team, days_from_today), do: team |> today() |> Date.add(days_from_today)

  test "a member with no away period is active, and the sidebar says so", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    assert has_element?(lv, "#standing-now", "Active")
    assert has_element?(lv, "#member-standing", "Active")
    assert has_element?(lv, "#no-away-periods")
  end

  test "adding an away period makes the member away, and the history records it",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    ends_on = day(team, 30)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    lv
    |> form("#away-form",
      away: %{
        starts_on: today(team),
        ends_on: ends_on,
        reason: "  Parental leave  "
      }
    )
    |> render_submit()

    assert has_element?(
             lv,
             "#standing-now",
             "Away until #{Service.Format.day_long(ends_on)} (Parental leave)"
           )

    assert has_element?(lv, "#away-period-list", "Parental leave")

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
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

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
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

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

  test "a member marked not a person cannot get an away period", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{not_a_person: true})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    refute has_element?(lv, "#away-form")
    assert has_element?(lv, "#away-not-a-person")

    params = %{"starts_on" => today(team), "ends_on" => day(team, 10), "reason" => "Leave"}
    assert AddAwayPeriod.call(team, member.id, user, params) == :not_a_person
    assert Repo.all(MemberAwayPeriod) == []
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

  test "a check-in lists the day, who recorded it, and what they heard", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    assert has_element?(lv, "#no-check-ins")

    lv
    |> form("#check-in-form",
      check_in: %{checked_in_on: day(team, -2), note: "Busy with school, back in January."}
    )
    |> render_submit()

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
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

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

  test "suggests marking a bot, and the switch marks it not a person", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    bot = member_fixture(team, %{name: "Roster Bot", phone: nil, email: nil})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{bot.id}/standing")

    assert has_element?(lv, "#not-a-person-suggestion")
    refute has_element?(lv, "#not-a-person-switch[checked]")

    lv |> element("#not-a-person-switch") |> render_click()

    assert has_element?(lv, "#not-a-person-switch[checked]")
    refute has_element?(lv, "#not-a-person-suggestion")
    assert Repo.reload!(bot).not_a_person
    assert has_element?(lv, "#standing-now", "Not a person")

    lv |> element("#not-a-person-switch") |> render_click()

    refute Repo.reload!(bot).not_a_person
  end

  test "does not suggest marking a member with attendance", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{phone: nil, email: nil})
    attendance_fixture(activity_fixture(team), member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/standing")

    refute has_element?(lv, "#not-a-person-suggestion")
  end
end

defmodule Web.MemberStandingLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberStandingChange
  alias App.Operation.AddAwayPeriod
  alias App.Operation.DeleteAwayPeriod
  alias App.Operation.EndAwayPeriod
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

  test "another team's away period cannot be ended or deleted" do
    %{user: user, team: team} = user_with_team_fixture()
    other = member_fixture(team_fixture())
    period = away_period_fixture(other, day(team, -5), day(team, 10))

    assert_raise Ecto.NoResultsError, fn -> DeleteAwayPeriod.call(team, period.id, user) end
    assert_raise Ecto.NoResultsError, fn -> EndAwayPeriod.call(team, period.id, user) end
    assert_raise Ecto.NoResultsError, fn -> AddAwayPeriod.call(team, other.id, user, %{}) end
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

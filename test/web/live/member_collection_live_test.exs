defmodule Web.MemberCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders members collection", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members")

    assert html =~ "Members"
  end

  test "lists current members missing a mobile phone or an email, and what they lack",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    no_phone = member_fixture(team, %{phone: nil})
    no_email = member_fixture(team, %{email: ""})
    neither = member_fixture(team, %{phone: "", email: nil})
    complete = member_fixture(team)
    departed = member_fixture(team, %{phone: nil, left_at: ~U[2025-01-01 00:00:00Z]})
    other_team = member_fixture(team_fixture(), %{phone: nil})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members?details=missing")

    assert has_element?(lv, "#missing-#{no_phone.id}", "Mobile phone")
    assert has_element?(lv, "#missing-#{no_email.id}", "Email")
    assert has_element?(lv, "#missing-#{neither.id}", "Mobile phone, Email")
    refute has_element?(lv, "#missing-#{complete.id}")
    refute has_element?(lv, "#missing-#{departed.id}")
    refute has_element?(lv, "#missing-#{other_team.id}")
  end

  test "the Group filter lists the group's members only", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    rope = group_fixture(team, %{title: "Rope rescue"})
    in_rope = member_fixture(team, %{name: "Avery Rope"})
    member_fixture(team, %{name: "Blake Ground"})
    group_member_fixture(rope, in_rope)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members")

    lv |> form("#member_filter_form", form: %{group: rope.id}) |> render_change()

    assert has_element?(lv, "#member_collection", "Avery Rope")
    refute has_element?(lv, "#member_collection", "Blake Ground")
    assert has_element?(lv, ".filter-bar-chips a", "Rope rescue")
  end

  test "another team's group finds no one", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    other_team = team_fixture()
    other_group = group_fixture(other_team)
    group_member_fixture(other_group, member_fixture(other_team, %{name: "Other Member"}))
    member_fixture(team, %{name: "Our Member"})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members?group=#{other_group.id}")

    refute has_element?(lv, "#member_collection", "Our Member")
    refute has_element?(lv, "#member_collection", "Other Member")
  end

  test "lists members not at an activity in the team's time frame, with when they last were",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    joined = ~U[2025-01-01 00:00:00Z]
    old = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), -200, :day)})
    recent = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), -10, :day)})
    drifting = member_fixture(team, %{joined_at: joined})
    attendance_fixture(old, drifting)
    never = member_fixture(team, %{joined_at: joined})
    seen = member_fixture(team, %{joined_at: joined})
    attendance_fixture(recent, seen)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members?attended=not-recent")

    assert has_element?(lv, "#member_filter_form select[name='form[attended]']")
    assert has_element?(lv, "#last-attended-#{drifting.id}")
    refute has_element?(lv, "#last-attended-#{drifting.id}", "Never")
    assert has_element?(lv, "#last-attended-#{never.id}", "Never")
    refute has_element?(lv, "#last-attended-#{seen.id}")
  end

  test "leaves out the Attended filter when the team turned it off", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    team |> Ecto.Changeset.change(not_seen_days: nil) |> App.Repo.update!()

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members")

    refute has_element?(lv, "#member_filter_form select[name='form[attended]']")
  end
end

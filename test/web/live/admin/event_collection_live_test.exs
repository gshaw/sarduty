defmodule Web.Admin.EventCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Event

  test "sums up the sync, and filters events by kind and team", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    admin = make_admin(user)
    other = team_fixture()

    Event.record!(:d4h_sync_round, duration_ms: 4200, data: %{teams: 12, outcome: "success"})
    sync = Event.record!(:d4h_team_sync, team_id: team.id, data: %{outcome: "failed"})
    other_sync = Event.record!(:d4h_team_sync, team_id: other.id, data: %{outcome: "changed"})

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/events")

    assert has_element?(lv, "#last-round", "12 teams in 4.2 s, success")
    assert has_element?(lv, "#last-run", "None yet")
    assert has_element?(lv, "#last-day", "1 failed sync")
    assert has_element?(lv, "#event-#{sync.id}")

    lv
    |> form("#event_filter_form", form: %{kind: "d4h_team_sync", team: team.id})
    |> render_change()

    assert_patch(lv, ~p"/admin/events?kind=d4h_team_sync&team=#{team.id}")
    assert has_element?(lv, "#event-#{sync.id}", "outcome: failed")
    refute has_element?(lv, "#event-#{other_sync.id}")
  end

  test "lists the IPs with the most wrong codes, and filters by IP", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    admin = make_admin(user)

    [miss | _] = for _ <- 1..3, do: Event.record!(:login_code_missed, ip: "203.0.113.9")
    Event.record!(:login_blocked, ip: "203.0.113.9", data: %{scope: "ip"})
    Event.record!(:login_code_missed, ip: "198.51.100.4")
    login = Event.record!(:logged_in, ip: "198.51.100.4", user_agent: "Safari/18")

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/events")

    assert has_element?(lv, "#last-week", "1 login, 4 wrong codes, 1 block")
    assert has_element?(lv, "#top-ip-1", "203.0.113.9")
    assert has_element?(lv, "#top-ip-2", "198.51.100.4")
    assert has_element?(lv, "#event-#{login.id} [title='Safari/18']", "198.51.100.4")

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/events?ip=198.51.100.4")
    assert has_element?(lv, "#event-#{login.id}")
    refute has_element?(lv, "#event-#{miss.id}")
  end

  test "is for admins only", %{conn: conn} do
    %{user: user} = user_with_team_fixture()

    assert {:error, {:redirect, _}} = live(log_in_user(conn, user), ~p"/admin/events")
  end
end

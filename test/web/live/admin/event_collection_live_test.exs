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
    Event.record!(:logged_in, ip: "198.51.100.5", data: %{via: "passkey"})

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/events")

    assert has_element?(lv, "#last-week", "2 logins, 1 with a passkey, 4 wrong codes, 1 block")
    assert has_element?(lv, "#top-ip-1", "203.0.113.9")
    assert has_element?(lv, "#top-ip-2", "198.51.100.4")
    assert has_element?(lv, "#event-#{login.id} [title='Safari/18']", "198.51.100.4")

    lv |> form("#event_filter_form", form: %{ip: "198.51.100.4"}) |> render_submit()
    assert_patch(lv, ~p"/admin/events?ip=198.51.100.4")
    assert has_element?(lv, "#event-#{login.id}")
    refute has_element?(lv, "#event-#{miss.id}")
  end

  test "counts an IPv6 /64 as one IP, and lists the emails with the most misses", %{
    conn: conn
  } do
    %{user: user} = user_with_team_fixture()
    admin = make_admin(user)
    guessed = "guessed@example.org"

    for n <- 1..3,
        do: Event.record!(:login_code_missed, ip: "2001:db8:1:2::#{n}", email_or_phone: guessed)

    Event.record!(:login_blocked,
      ip: "2001:db8:1:2::9",
      email_or_phone: guessed,
      data: %{scope: "account"}
    )

    other = Event.record!(:login_code_missed, ip: "198.51.100.4", email_or_phone: "x@example.org")
    Event.record!(:login_code_requested, ip: "198.51.100.4", email_or_phone: "y@example.org")

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/events")

    assert has_element?(lv, "#top-ip-1", "2001:db8:1:2::/64")
    assert has_element?(lv, "#top-ip-1", "4")
    assert has_element?(lv, "#top-account-1", guessed)
    assert has_element?(lv, "#top-account-1", "4")
    refute has_element?(lv, "#top-account-3")

    lv |> element("#top-account-1 a") |> render_click()
    assert_patch(lv, ~p"/admin/events?who=#{guessed}")
    refute has_element?(lv, "#event-#{other.id}")

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/events?ip=2001:db8:1:2::/64")
    assert lv |> element("#events") |> render() =~ "2001:db8:1:2::3"
    refute has_element?(lv, "#event-#{other.id}")
  end

  test "searches by email or number, however it was typed", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    admin = make_admin(user)
    texted = Event.record!(:login_code_missed, email_or_phone: {:phone, "+16045550142"})
    emailed = Event.record!(:login_code_missed, email_or_phone: "Dana@example.org")
    other = Event.record!(:login_code_missed, email_or_phone: "x@example.org")

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/events")
    assert has_element?(lv, "#event-#{texted.id}", "+16045550142")

    lv |> form("#event_filter_form", form: %{who: "604 555 0142"}) |> render_change()
    assert has_element?(lv, "#event-#{texted.id}")
    refute has_element?(lv, "#event-#{other.id}")

    lv |> form("#event_filter_form", form: %{who: "dana@EXAMPLE.org"}) |> render_change()
    assert has_element?(lv, "#event-#{emailed.id}")
    refute has_element?(lv, "#event-#{texted.id}")
  end

  test "shows the hash for an event from before emails were kept", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    admin = make_admin(user)
    who = Event.who("old@example.org")

    old =
      App.Repo.insert!(%Event{
        kind: :login_code_missed,
        who: who,
        occurred_at: DateTime.utc_now()
      })

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/events")
    assert has_element?(lv, "#event-#{old.id} a", who)
    assert has_element?(lv, "#top-account-1 a", who)

    lv |> element("#event-#{old.id} a") |> render_click()
    assert_patch(lv, ~p"/admin/events?who=#{who}")
    assert has_element?(lv, "#event-#{old.id}")
  end

  test "is for admins only", %{conn: conn} do
    %{user: user} = user_with_team_fixture()

    assert_raise Web.Status.NotFound, fn -> live(log_in_user(conn, user), ~p"/admin/events") end
  end
end

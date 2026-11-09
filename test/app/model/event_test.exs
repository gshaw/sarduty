defmodule App.Model.EventTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.Event
  alias App.Model.TeamLoginGrant

  @now ~U[2026-10-07 12:00:00.000000Z]

  test "counts a kind since a time, and by what its data says" do
    team = team_fixture()
    earlier = DateTime.add(@now, -2, :hour)
    Event.record!(:d4h_team_sync, team_id: team.id, data: %{outcome: "failed"}, occurred_at: @now)

    Event.record!(:d4h_team_sync,
      team_id: team.id,
      data: %{outcome: "changed"},
      occurred_at: @now
    )

    Event.record!(:d4h_team_sync, data: %{outcome: "failed"}, occurred_at: earlier)

    since = DateTime.add(@now, -1, :hour)
    assert Event.count_since(:d4h_team_sync, since) == 2
    assert Event.count_since(:d4h_team_sync, since, data: %{outcome: "failed"}) == 1
    assert Event.count_since(:d4h_rate_limited, since) == 0
  end

  test "lists the newest first, filtered by kind and team" do
    team = team_fixture()
    other = team_fixture()
    old = Event.record!(:d4h_team_sync, team_id: team.id, occurred_at: DateTime.add(@now, -1))
    new = Event.record!(:d4h_team_sync, team_id: team.id, occurred_at: @now)
    Event.record!(:d4h_team_sync, team_id: other.id, occurred_at: @now)
    Event.record!(:d4h_rate_limited, team_id: team.id, occurred_at: @now)

    events = Event.get_recent(%{kind: :d4h_team_sync, team_id: team.id}, 10)
    assert Enum.map(events, & &1.id) == [new.id, old.id]
    assert length(Event.get_recent(%{}, 10)) == 4
    assert length(Event.get_recent(%{}, 2)) == 2
  end

  test "keeps who and the IP as the limits count it, and counts by each" do
    who = Event.who("guessed@example.org")
    event = Event.record!(:login_code_missed, ip: "2001:db8:1:2::7", who: who, occurred_at: @now)
    assert %Event{ip: "2001:db8:1:2::7", ip_key: "2001:db8:1:2::/64", who: ^who} = event
    assert Event.record!(:logged_in, ip: "203.0.113.7").ip_key == "203.0.113.7"
    assert Event.record!(:d4h_sync_round).ip_key == nil

    Event.record!(:login_code_missed, ip: "2001:db8:1:2::8", occurred_at: @now)

    since = DateTime.add(@now, -1, :hour)
    assert Event.count_since(:login_code_missed, since, who: who) == 1
    assert Event.count_since(:login_code_missed, since, ip_key: "2001:db8:1:2::/64") == 2
    assert Event.count_since(:login_code_missed, since, ip_key: "2001:db8:1:3::/64") == 0

    Event.record!(:login_code_missed, who: who, data: %{known_browser: true}, occurred_at: @now)
    assert Event.count_since(:login_code_missed, since, who: who) == 2

    assert Event.count_since(:login_code_missed, since, who: who, data: %{known_browser: true}) ==
             1
  end

  test "prunes each kind past its retention" do
    old = Event.record!(:d4h_sync_round, occurred_at: DateTime.add(@now, -91, :day))
    kept = Event.record!(:d4h_sync_round, occurred_at: DateTime.add(@now, -89, :day))

    assert Event.prune(@now) == 1
    refute Repo.get(Event, old.id)
    assert Repo.get(Event, kept.id)
  end

  test "a login grant, added and removed, is recorded without its email" do
    team = team_fixture()
    TeamLoginGrant.grant!(team, "Office@Example.org", "shared inbox")
    TeamLoginGrant.revoke!(team, "office@example.org")
    TeamLoginGrant.revoke!(team, "office@example.org")

    who = Event.who("office@example.org")
    assert %Event{team_id: team_id, who: ^who, data: data} = Event.get_last(:login_grant_added)
    assert data == %{}
    assert team_id == team.id
    assert Event.count_since(:login_grant_removed, DateTime.add(@now, -1, :day)) == 1
  end

  test "cuts a long user agent to fit" do
    event = Event.record!(:d4h_rate_limited, user_agent: String.duplicate("a", 400))
    assert String.length(event.user_agent) == 255
  end
end

defmodule Web.MeQualificationsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture()
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  test "lists qualifications soonest expiry first, with days left on the expiring one",
       %{conn: conn, team: team, member: member} do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    first_aid = qualification_fixture(team, %{title: "First Aid"})
    rope = qualification_fixture(team, %{title: "Rope Rescue"})
    avalanche = qualification_fixture(team, %{title: "Avalanche"})
    other_team = qualification_fixture(team_fixture(), %{title: "Other team's"})

    qualification_award_fixture(first_aid, member, %{
      starts_at: ~U[2019-03-04 19:00:00Z],
      ends_at: DateTime.add(now, -300, :day)
    })

    qualification_award_fixture(first_aid, member, %{ends_at: DateTime.add(now, 30, :day)})
    qualification_award_fixture(rope, member)

    qualification_award_fixture(avalanche, member, %{
      starts_at: ~U[2020-01-15 19:00:00Z],
      ends_at: ~U[2024-09-15 19:00:00Z]
    })

    qualification_award_fixture(other_team, member)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/qualifications")

    assert has_element?(lv, "#qualifications-#{first_aid.id} .badge", "30 days")
    assert has_element?(lv, "#qualifications-#{first_aid.id}", "2019")
    assert has_element?(lv, "#qualifications-#{rope.id}", "Does not expire")
    refute has_element?(lv, "#qualifications-#{rope.id} .badge")
    assert has_element?(lv, "#qualifications-#{avalanche.id}.is-muted", "Expired Sep 15, 2024")
    refute has_element?(lv, ".table-group-row")
    refute has_element?(lv, "#qualifications-#{other_team.id}")
    refute has_element?(lv, "[id^=qualifications-award-]")
  end
end

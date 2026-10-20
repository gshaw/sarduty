defmodule Web.MemberQualificationsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  defp awards(team, member) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    first_aid = qualification_fixture(team, %{title: "First Aid"})

    old =
      qualification_award_fixture(first_aid, member, %{
        starts_at: ~U[2019-03-04 19:00:00Z],
        ends_at: ~U[2022-03-04 19:00:00Z]
      })

    latest =
      qualification_award_fixture(first_aid, member, %{
        starts_at: ~U[2022-03-04 19:00:00Z],
        ends_at: DateTime.add(now, 400, :day)
      })

    %{first_aid: first_aid, old: old, latest: latest}
  end

  test "a team admin sees the member's qualifications grouped, with each earlier award",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    %{first_aid: first_aid, old: old} = awards(team, member)
    other_member = member_fixture(team)
    qualification_award_fixture(qualification_fixture(team), other_member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/qualifications")

    row = "#member-qualifications-later #member-qualifications-#{first_aid.id}"

    assert has_element?(
             lv,
             ~s{#{row} a[href="/teams/#{team.subdomain}/qualifications/#{first_aid.id}"]}
           )

    assert has_element?(
             lv,
             "#{row} #member-qualifications-award-#{old.id}",
             "Mar 2019 – Mar 2022"
           )

    assert has_element?(lv, row, "2019")
    assert lv |> element("#member-qualifications") |> render() |> String.contains?("First Aid")
    refute has_element?(lv, "[id^=remove-award-]")
  end

  test "a team on SAR Duty Records can remove the latest award or an earlier one",
       %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
    member = Repo.get_by!(App.Model.Member, team_id: team.id, email: user.email)
    %{old: old, latest: latest} = awards(team, member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/qualifications")

    assert has_element?(lv, "#remove-award-#{latest.id}")
    assert has_element?(lv, "#member-qualifications-award-#{old.id} #remove-award-#{old.id}")
  end

  test "says when the member has none", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/qualifications")

    assert has_element?(lv, "#no-qualifications")
  end
end

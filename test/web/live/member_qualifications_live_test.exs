defmodule Web.MemberQualificationsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.D4H
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

  test "a team admin sees the member's qualifications, with each earlier award",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    %{first_aid: first_aid, old: old} = awards(team, member)
    other_member = member_fixture(team)
    qualification_award_fixture(qualification_fixture(team), other_member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/qualifications")

    row = "#member-qualifications-#{first_aid.id}"

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
    refute has_element?(lv, "#{row} .badge")
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

  describe "for a member (#440)" do
    setup %{conn: conn} do
      team =
        %{d4h_api_host: D4H.records_host()}
        |> member_logins_team_fixture()
        |> Ecto.Changeset.change(d4h_access_key: "sdr_key")
        |> Repo.update!()

      viewer = member_fixture(team, %{d4h_permission: 2})
      user = App.AccountsFixtures.user_fixture(%{email: viewer.email})
      %{conn: log_in_user(conn, user), team: team}
    end

    test "the team admin's columns, with no links, Certificate, or Remove",
         %{conn: conn, team: team} do
      other = member_fixture(team)
      %{first_aid: first_aid, old: old} = awards(team, other)
      certificate_award_fixture(team, other)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{other.id}/qualifications")

      row = "#member-qualifications-#{first_aid.id}"
      assert has_element?(lv, row, "First Aid")
      refute has_element?(lv, "#{row} a")
      refute has_element?(lv, "[id^=certificate-]")
      assert has_element?(lv, "th", "First held")
      assert has_element?(lv, "#member-qualifications-award-#{old.id}")
      refute has_element?(lv, "[id^=remove-award-]")
      refute has_element?(lv, "#award-qualification")
    end

    # The page opens to members; its actions don't. Web.UserAuth drops the event before
    # the page's handle_event, which on a Records team would remove the award.
    test "an award event from a member changes nothing", %{conn: conn, team: team} do
      other = member_fixture(team)
      %{latest: latest} = awards(team, other)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{other.id}/qualifications")
      render_click(lv, "remove-award", %{"id" => "#{latest.id}"})
      render_click(lv, "award", %{"award" => %{"qualification_id" => ""}})

      assert Repo.get(App.Model.MemberQualificationAward, latest.id)
      assert has_element?(lv, "#member-qualifications")
    end
  end
end

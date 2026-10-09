defmodule Web.TitledRecordFormLiveTest do
  # Qualifications and groups of a team on SAR Duty Records (docs/records.md), and a
  # member's awards and groups on their tabs.
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.RecordsStub
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
    member = Repo.get_by!(App.Model.Member, team_id: team.id, email: user.email)
    %{conn: log_in_user(conn, user), team: team, member: member}
  end

  defp stub, do: RecordsStub.stub(&reply/3)

  defp reply("POST", "/member-qualification-awards", _body) do
    {200,
     %{
       "id" => 300,
       "member" => %{"resourceType" => "Member", "id" => 1},
       "qualification" => %{"id" => 1},
       "startsAt" => "2026-05-01T07:00:00Z"
     }}
  end

  defp reply("POST", "/member-group-memberships", _body) do
    {200,
     %{
       "id" => 400,
       "member" => %{"resourceType" => "Member", "id" => 1},
       "group" => %{"id" => 1}
     }}
  end

  defp reply(_method, _path, body) do
    {200, Map.merge(%{"id" => 99, "title" => "Rope Team"}, body || %{})}
  end

  defp add(conn, team, path, title) do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/#{path}/new")
    lv |> form("#titled-record-form", form: %{title: title}) |> render_submit()
  end

  test "a qualification is added, renamed, and deleted", %{conn: conn, team: team} do
    stub()
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/qualifications")
    assert has_element?(list, "#qualification-add")

    add(conn, team, "qualifications", "Swiftwater Rescue")

    assert_received {:records, "POST", "/member-qualifications",
                     %{"title" => "Swiftwater Rescue"}}

    qualification = qualification_fixture(team, %{title: "Swiftwater", d4h_qualification_id: 99})
    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}")
    assert has_element?(page, "#qualification-actions #qualification-edit")

    {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}/edit")
    edit |> form("#titled-record-form", form: %{title: "Swiftwater Rescue 2"}) |> render_submit()

    assert_received {:records, "PATCH", "/member-qualifications/99",
                     %{"title" => "Swiftwater Rescue 2"}}

    {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}/edit")
    edit |> element("#record-delete-button") |> render_click()
    assert_received {:records, "DELETE", "/member-qualifications/99", nil}
  end

  test "a qualification is awarded on a member's tab, and removed",
       %{conn: conn, team: team, member: member} do
    stub()
    qualification = qualification_fixture(team, %{d4h_qualification_id: 99})

    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")

    tab
    |> form("#award-form",
      award: %{qualification_id: qualification.id, starts_on: "2026-05-01", ends_on: "2029-05-01"}
    )
    |> render_submit()

    assert_received {:records, "POST", "/member-qualification-awards", body}

    assert body == %{
             "qualificationId" => 99,
             "memberId" => member.d4h_member_id,
             "startsAt" => "2026-05-01T07:00:00Z",
             "endsAt" => "2029-05-01T07:00:00Z"
           }

    award = qualification_award_fixture(qualification, member)
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")
    tab |> element("#remove-award-#{award.id}") |> render_click()

    path = "/member-qualification-awards/#{award.d4h_award_id}"
    assert_received {:records, "DELETE", ^path, nil}
  end

  test "an award needs a qualification and a start, listed in the summary",
       %{conn: conn, team: team, member: member} do
    qualification_fixture(team)
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")
    tab |> form("#award-form", award: %{starts_on: ""}) |> render_submit()

    assert has_element?(tab, "#award-form .error-summary", "Select a qualification.")
    assert has_element?(tab, "#award-form .error-summary", "Enter the day it starts.")
  end

  test "a group is added, joined, left, and deleted", %{conn: conn, team: team, member: member} do
    stub()
    add(conn, team, "groups", "Rope Team")
    assert_received {:records, "POST", "/member-groups", %{"title" => "Rope Team"}}

    group = group_fixture(team, %{title: "Rope Team", d4h_group_id: 99})
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/groups")
    tab |> form("#add-group-form", %{group_id: group.id}) |> render_submit()

    assert_received {:records, "POST", "/member-group-memberships", body}
    assert body == %{"groupId" => 99, "memberId" => member.d4h_member_id}

    group_member = group_member_fixture(group, member)
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/groups")
    tab |> element("#remove-group-#{group_member.id}") |> render_click()

    path = "/member-group-memberships/#{group_member.d4h_group_membership_id}"
    assert_received {:records, "DELETE", ^path, nil}

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/groups/#{group.id}")
    assert has_element?(page, "#group-actions #group-edit")

    {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/groups/#{group.id}/edit")
    edit |> element("#record-delete-button") |> render_click()
    assert_received {:records, "DELETE", "/member-groups/99", nil}
  end

  test "a title is needed", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/groups/new")
    lv |> form("#titled-record-form", form: %{title: ""}) |> render_submit()
    assert has_element?(lv, "#titled-record-form .error-summary", "Enter a title.")
  end

  test "a D4H team has no such pages, buttons, or tab forms", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)
    member = member_fixture(team)
    qualification_fixture(team)
    group_fixture(team)

    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/qualifications")
    refute has_element?(list, "#qualification-add")
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/groups")
    refute has_element?(list, "#group-add")
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")
    refute has_element?(tab, "#award-form")
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/groups")
    refute has_element?(tab, "#add-group-form")

    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/groups/new") end
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/qualifications/new") end
  end
end

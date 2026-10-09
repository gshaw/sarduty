defmodule Web.TitledRecordFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = hosted_team_with_user_fixture()
    member = Repo.get_by!(Member, team_id: team.id)
    %{conn: log_in_user(conn, user), team: team, member: member}
  end

  defp add(conn, team, path, title) do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/#{path}/new")

    lv
    |> form("#titled-record-form", form: %{title: title})
    |> render_submit()
    |> follow_redirect(conn)
  end

  test "a qualification is added, awarded, removed, renamed, and deleted", %{
    conn: conn,
    team: team,
    member: member
  } do
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/qualifications")
    assert has_element?(list, "#qualification-add")

    {:ok, page, html} = add(conn, team, "qualifications", "Swiftwater Rescue")
    assert html =~ "Saved Swiftwater Rescue."
    assert has_element?(page, "#qualification-edit")
    qualification = Repo.get_by!(Qualification, team_id: team.id, title: "Swiftwater Rescue")

    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")

    tab
    |> form("#award-form",
      award: %{qualification_id: qualification.id, starts_on: "2026-05-01", ends_on: "2029-05-01"}
    )
    |> render_submit()

    award =
      Repo.get_by!(MemberQualificationAward,
        member_id: member.id,
        qualification_id: qualification.id
      )

    assert award.starts_at == ~U[2026-05-01 03:00:00Z]

    tab |> element("#remove-award-#{award.id}") |> render_click()
    refute Repo.get_by(MemberQualificationAward, member_id: member.id)

    {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}/edit")
    edit |> form("#titled-record-form", form: %{title: "Swiftwater"}) |> render_submit()
    assert Repo.reload!(qualification).title == "Swiftwater"

    {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}/edit")
    edit |> element("#record-delete-button") |> render_click()
    refute Repo.get_by(Qualification, team_id: team.id, title: "Swiftwater")
  end

  test "a group is added, joined, left, and deleted", %{conn: conn, team: team, member: member} do
    {:ok, _page, _html} = add(conn, team, "groups", "Rope Team")
    group = Repo.get_by!(Group, team_id: team.id, title: "Rope Team")

    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/groups")
    tab |> form("#add-group-form", %{group_id: group.id}) |> render_submit()
    group_member = Repo.get_by!(GroupMember, member_id: member.id, group_id: group.id)

    tab |> element("#remove-group-#{group_member.id}") |> render_click()
    refute Repo.get_by(GroupMember, member_id: member.id)

    {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/groups/#{group.id}/edit")
    edit |> element("#record-delete-button") |> render_click()
    refute Repo.get_by(Group, team_id: team.id, title: "Rope Team")
  end

  test "a title is needed", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/groups/new")
    html = lv |> form("#titled-record-form", form: %{title: ""}) |> render_submit()
    assert html =~ "Enter a title."
  end

  test "a D4H team has no such pages", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/groups/new") end
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/qualifications/new") end
  end
end

defmodule Web.MemberFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Model.Member
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = hosted_team_with_user_fixture()
    %{conn: log_in_user(conn, user), team: team, user: user}
  end

  test "a team admin adds a member, who shows up in the list", %{conn: conn, team: team} do
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/members")
    assert has_element?(list, "#member-add")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/new")

    {:ok, _lv, html} =
      lv
      |> form("#member-form",
        form: %{name: "Casey New", email: "casey@example.com", joined_on: "2026-01-15"}
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Saved Casey New."
    member = Repo.get_by!(Member, team_id: team.id, name: "Casey New")
    assert member.email == "casey@example.com"
    assert member.d4h_permission == 2
    assert Repo.get_by!(ChangeSet, team_id: team.id, source: :edit)
  end

  test "the only team admin can't stop being one or leave", %{conn: conn, team: team} do
    member = Repo.get_by!(Member, team_id: team.id, name: "Robin Example")
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")

    html = lv |> form("#member-form", form: %{team_admin: "false"}) |> render_submit()
    assert html =~ "Make another member a team admin first."

    assert lv |> element("#member-leave") |> render_click() =~
             "Make another member a team admin first."

    assert Repo.reload!(member).d4h_permission == 0
  end

  test "a team admin changes a member's details and marks them as left", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/new")

    lv
    |> form("#member-form",
      form: %{
        name: "Second Admin",
        email: "second@example.com",
        joined_on: "2026-01-15",
        team_admin: "true"
      }
    )
    |> render_submit()

    member = Repo.get_by!(Member, team_id: team.id, name: "Robin Example")
    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}")
    assert has_element?(page, "#member-edit")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")

    lv
    |> form("#member-form", form: %{position: "Training Officer"})
    |> render_submit()

    assert Repo.reload!(member).position == "Training Officer"

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")
    lv |> element("#member-leave") |> render_click()
    assert Repo.reload!(member).d4h_status == "RETIRED"
  end

  test "a name is needed", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/new")
    html = lv |> form("#member-form", form: %{name: ""}) |> render_submit()
    assert html =~ "Enter the member&#39;s name."
  end

  # The scoping test's team has D4H, so its 404 comes before the member is read.
  test "another team's member 404s", %{conn: conn, team: team} do
    other = member_fixture(team_fixture())

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/teams/#{team}/members/#{other.id}/edit")
    end
  end

  test "a D4H team has no such page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)

    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/members/new") end
  end
end

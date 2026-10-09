defmodule Web.MemberFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.RecordsStub
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
    admin = Repo.get_by!(Member, team_id: team.id, email: user.email)
    %{conn: log_in_user(conn, user), team: team, admin: admin}
  end

  defp stub_ok,
    do: RecordsStub.stub(fn _method, _path, _body -> {200, RecordsStub.member_json(77)} end)

  test "a team admin adds a member through Records", %{conn: conn, team: team} do
    stub_ok()
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/members")
    assert has_element?(list, "#member-add")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/new")

    {:ok, _lv, html} =
      lv
      |> form("#member-form",
        form: %{name: "Casey New", email: "Casey@Example.com", joined_on: "2026-01-15"}
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Saved Casey New."

    assert_received {:records, "POST", "/members", body}
    assert body["name"] == "Casey New"
    assert body["email"] == "casey@example.com"
    assert body["permission"] == 2
    assert body["startsAt"] == "2026-01-15T08:00:00Z"

    change_set = Repo.get_by!(ChangeSet, team_id: team.id, source: :edit)

    assert [%ChangeSetRow{action: :create_member, status: :applied, d4h_record_id: 77}] =
             Repo.preload(change_set, :rows).rows
  end

  test "the only team admin cannot stop being one or leave", %{
    conn: conn,
    team: team,
    admin: admin
  } do
    stub_ok()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/edit")

    html = lv |> form("#member-form", form: %{team_admin: "false"}) |> render_submit()
    assert html =~ "Make another member a team admin first."

    assert lv |> element("#member-leave") |> render_click() =~
             "Make another member a team admin first."

    refute_received {:records, _method, _path, _body}
  end

  test "a change sends only what changed, and leaving is a retire",
       %{conn: conn, team: team, admin: admin} do
    stub_ok()
    manager_fixture(team)

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}")
    assert has_element?(page, "#member-actions #member-edit")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/edit")
    lv |> form("#member-form", form: %{position: "Training Officer"}) |> render_submit()

    path = "/members/#{admin.d4h_member_id}"
    assert_received {:records, "PATCH", ^path, %{"position" => "Training Officer"} = body}
    assert map_size(body) == 1

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{admin.id}/edit")
    lv |> element("#member-leave") |> render_click()

    retire = "/members/#{admin.d4h_member_id}/retire"
    assert_received {:records, "PATCH", ^retire, %{"direction" => "RETIRE"}}
  end

  test "a retired member is marked as rejoined", %{conn: conn, team: team} do
    stub_ok()
    member = member_fixture(team, %{d4h_status: "RETIRED", left_at: ~U[2026-01-01 08:00:00Z]})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")
    lv |> element("#member-rejoin") |> render_click()

    retire = "/members/#{member.d4h_member_id}/retire"
    assert_received {:records, "PATCH", ^retire, %{"direction" => "UNRETIRE"}}
  end

  test "Records' refusal shows as the error", %{conn: conn, team: team} do
    RecordsStub.stub(fn _method, _path, _body -> {400, %{"title" => "Enter a shorter name."}} end)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/new")

    html =
      lv
      |> form("#member-form", form: %{name: "Casey New", joined_on: "2026-01-15"})
      |> render_submit()

    assert html =~ "Enter a shorter name."
  end

  test "a name is needed, and the error summary lists it", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/new")
    lv |> form("#member-form", form: %{name: "", joined_on: ""}) |> render_submit()

    assert has_element?(lv, "#member-form .error-summary", "Enter the member's name.")
  end

  test "another team's member 404s", %{conn: conn, team: team} do
    other = member_fixture(team_fixture())

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/teams/#{team}/members/#{other.id}/edit")
    end
  end

  test "a D4H team has no such page and no add button", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)

    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/members")
    refute has_element?(list, "#member-add")
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/members/new") end
  end
end

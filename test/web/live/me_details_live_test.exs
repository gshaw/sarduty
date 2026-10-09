defmodule Web.MeDetailsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.D4H
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture(%{address: "1 Main St"})
    team = team |> Ecto.Changeset.change(d4h_access_key: "key") |> Repo.update!()
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  defp d4h_member(team, member, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => member.d4h_member_id,
        "name" => member.name,
        "owner" => %{"resourceType" => "Team", "id" => team.d4h_team_id},
        "email" => %{"value" => member.email},
        "mobile" => %{"phone" => nil},
        "deprecatedAddress" => "1 Main St",
        "primaryEmergencyContact" => %{
          "name" => "Sam Rivera",
          "relation" => "Partner",
          "primaryPhone" => "604-555-0100",
          "secondaryPhone" => ""
        },
        "secondaryEmergencyContact" => nil
      },
      overrides
    )
  end

  # D4H answers GETs with the member; each PATCH body comes to the test process.
  defp stub_d4h(team, member) do
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      case conn.method do
        "GET" ->
          Req.Test.json(conn, d4h_member(team, member))

        "PATCH" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test, {:patch, conn.request_path, Jason.decode!(body)})
          Req.Test.json(conn, d4h_member(team, member))
      end
    end)
  end

  test "shows what D4H holds now", %{conn: conn, team: team, member: member} do
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    assert has_element?(lv, "#details_contact1_name[value='Sam Rivera']")
    assert has_element?(lv, "#details_address", "1 Main St")
  end

  test "saves a change straight to D4H as the member's change set",
       %{conn: conn, team: team, member: member, user: user} do
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    lv
    |> form("#details-form",
      details: %{address: "2 Oak Ave", contact1_primary_phone: "604-555-0199"}
    )
    |> render_submit()

    assert_redirect(lv, ~p"/teams/#{team}/me")

    path = "/v3/team/#{team.d4h_team_id}/members/#{member.d4h_member_id}"
    assert_received {:patch, ^path, body}
    assert body["deprecatedAddress"] == "2 Oak Ave"
    assert body["primaryEmergencyContact"]["primaryPhone"] == "604-555-0199"
    assert body["primaryEmergencyContact"]["name"] == "Sam Rivera"
    refute Map.has_key?(body, "secondaryEmergencyContact")

    [change_set] = Repo.all(ChangeSet)
    assert {change_set.source, change_set.proposed_by_user_id} == {:member, user.id}
    [row] = Repo.all(ChangeSetRow)
    assert {row.status, row.member_id} == {:applied, member.id}
    assert Repo.reload!(member).address == "2 Oak Ave"
  end

  test "an unchanged form sends nothing", %{conn: conn, team: team, member: member} do
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    lv |> form("#details-form") |> render_submit()

    assert_redirect(lv, ~p"/teams/#{team}/me")
    refute_received {:patch, _path, _body}
    assert Repo.all(ChangeSet) == []
  end

  test "says so when D4H can't be read", %{conn: conn, team: team} do
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 500, ""))
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    assert has_element?(lv, "#details-error")
    refute has_element?(lv, "#details-form")
  end

  test "a team on SAR Duty Records changes only the address", %{conn: conn, member: member} do
    team =
      member.team
      |> Ecto.Changeset.change(d4h_api_host: D4H.records_host())
      |> Repo.update!()

    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/details")

    assert has_element?(lv, "#details_address")
    refute has_element?(lv, "#details_contact1_name")
  end

  test "a team admin page is still a 404 for the member", %{
    conn: conn,
    team: team,
    member: member
  } do
    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")
    end
  end
end

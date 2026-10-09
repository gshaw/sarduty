defmodule Web.HostedTeamPagesTest do
  # Every team page opens for a hosted team with sample data (docs/hosted-d4h.md), whose
  # D4H calls go to the store in-process. The mileage report is left out: it calls
  # Mapbox.
  use Web.ConnCase

  import App.DataFixtures

  alias App.Model.Activity
  alias App.Model.Group
  alias App.Model.Member
  alias App.Model.Qualification
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = hosted_team_with_user_fixture(%{sample_data: true})
    %{conn: log_in_user(conn, user), team: team}
  end

  test "every page opens", %{conn: conn, team: team} do
    member = Repo.get_by!(Member, team_id: team.id, name: "Avery Morrison")
    activity = Repo.get_by!(Activity, team_id: team.id, title: "Night navigation")
    group = Repo.get_by!(Group, team_id: team.id, title: "Ground Search")
    qualification = Repo.get_by!(Qualification, team_id: team.id, title: "Standard First Aid")
    t = team.subdomain

    paths = [
      "/teams/#{t}",
      "/teams/#{t}/activities",
      "/teams/#{t}/activities/new",
      "/teams/#{t}/activities/#{activity.id}",
      "/teams/#{t}/activities/#{activity.id}/edit",
      "/teams/#{t}/activities/#{activity.id}/attendance",
      "/teams/#{t}/activities/#{activity.id}/history",
      "/teams/#{t}/activities/#{activity.id}/take-attendance",
      "/teams/#{t}/members",
      "/teams/#{t}/members/new",
      "/teams/#{t}/members/#{member.id}",
      "/teams/#{t}/members/#{member.id}/edit",
      "/teams/#{t}/members/#{member.id}/groups",
      "/teams/#{t}/members/#{member.id}/qualifications",
      "/teams/#{t}/members/#{member.id}/card",
      "/teams/#{t}/members/#{member.id}/history",
      "/teams/#{t}/members/#{member.id}/image",
      "/teams/#{t}/groups",
      "/teams/#{t}/groups/new",
      "/teams/#{t}/groups/#{group.id}",
      "/teams/#{t}/groups/#{group.id}/edit",
      "/teams/#{t}/groups/#{group.id}/review",
      "/teams/#{t}/qualifications",
      "/teams/#{t}/qualifications/new",
      "/teams/#{t}/qualifications/#{qualification.id}",
      "/teams/#{t}/qualifications/#{qualification.id}/edit",
      "/teams/#{t}/tax-credit-letters",
      "/teams/#{t}/proposed-changes",
      "/teams/#{t}/settings",
      "/teams/#{t}/settings/cards",
      "/teams/#{t}/settings/managers",
      "/teams/#{t}/logo"
    ]

    for path <- paths do
      assert get(conn, path).status == 200, path
    end
  end

  test "the store's API answers over HTTP with the team's key", %{team: team} do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{team.d4h_access_key}")
      |> get("/d4h/v3/team/#{team.d4h_team_id}/members?size=2")

    assert %{"totalSize" => 11, "results" => [_, _]} = json_response(conn, 200)
    assert build_conn() |> get("/d4h/v3/whoami") |> json_response(401)
  end
end

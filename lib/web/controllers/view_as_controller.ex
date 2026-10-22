defmodule Web.ViewAsController do
  use Web, :controller

  alias App.Model.Member
  alias App.Operation.StartViewAs
  alias Web.UserAuth

  # A team admin views the team as one of its members (#425), to check the data and find
  # pages that break. The member id goes in the session, and Web.UserAuth applies it on
  # every page members open. Only team admins reach these routes.

  def create(conn, %{"id" => id}) do
    %{current_team: team, current_user: user} = conn.assigns
    member = Member.find!(team, id)
    :ok = StartViewAs.call(user, member)

    conn
    |> UserAuth.put_view_as(member)
    |> redirect(to: ~p"/teams/#{team}/me")
  end

  def delete(conn, _params) do
    team = conn.assigns.current_team
    {member_id, conn} = UserAuth.delete_view_as(conn)

    member = member_id && Member.find(team, member_id)
    to = if member, do: ~p"/teams/#{team}/members/#{member}", else: ~p"/teams/#{team}"
    redirect(conn, to: to)
  end
end

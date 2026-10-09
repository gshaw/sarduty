defmodule Web.TeamScopingTest do
  # A user on one team puts another team's record id in their own team's URL.
  # Every page must 404 before it reads the record, calls D4H, or calls Mapbox.
  use Web.ConnCase

  import App.DataFixtures

  alias App.Model.ChangeSet

  @templates [
    "/teams/:subdomain/activities/:id",
    "/teams/:subdomain/activities/:id/attendance",
    "/teams/:subdomain/activities/:id/edit",
    "/teams/:subdomain/activities/:id/history",
    "/teams/:subdomain/activities/:id/mileage",
    "/teams/:subdomain/activities/:id/take-attendance",
    "/teams/:subdomain/members/:id",
    "/teams/:subdomain/members/:id/edit",
    "/teams/:subdomain/members/:id/groups",
    "/teams/:subdomain/members/:id/qualifications",
    "/teams/:subdomain/members/:id/card",
    "/teams/:subdomain/members/:id/history",
    "/teams/:subdomain/members/:id/card/apple-wallet",
    "/teams/:subdomain/members/:id/card/google-wallet",
    "/teams/:subdomain/members/:id/image",
    "/teams/:subdomain/groups/:id",
    "/teams/:subdomain/groups/:id/edit",
    "/teams/:subdomain/groups/:id/review",
    "/teams/:subdomain/proposed-changes/:id",
    "/teams/:subdomain/qualifications/:id",
    "/teams/:subdomain/qualifications/:id/edit",
    "/teams/:subdomain/tax-credit-letters/:id",
    "/teams/:subdomain/tax-credit-letters/:id/pdf"
  ]

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    other_team = team_fixture()
    member = member_fixture(other_team)

    other = %{
      activity: activity_fixture(other_team),
      member: member,
      group: group_fixture(other_team),
      qualification: qualification_fixture(other_team),
      letter: tax_credit_letter_fixture(member),
      change_set:
        ChangeSet.propose!(
          %ChangeSet{team_id: other_team.id, source: :agent},
          []
        )
    }

    %{conn: log_in_user(conn, user), team: team, other: other}
  end

  test "every team route with an id is covered here" do
    routed =
      Web.Router.__routes__()
      |> Enum.map(& &1.path)
      |> Enum.filter(&(String.starts_with?(&1, "/teams/:subdomain/") and &1 =~ "/:id"))
      |> MapSet.new()

    assert MapSet.new(@templates) == routed
  end

  for template <- @templates do
    test "#{template} 404s for another team's record", %{conn: conn, team: team, other: other} do
      path = path_for(unquote(template), team.subdomain, other)

      assert_error_sent 404, fn -> get(conn, path) end
    end
  end

  defp path_for("/teams/:subdomain/members/:id/edit", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/edit"

  defp path_for("/teams/:subdomain/groups/:id/edit", s, o),
    do: ~p"/teams/#{s}/groups/#{o.group.id}/edit"

  defp path_for("/teams/:subdomain/qualifications/:id/edit", s, o),
    do: ~p"/teams/#{s}/qualifications/#{o.qualification.id}/edit"

  defp path_for("/teams/:subdomain/activities/:id", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}"

  defp path_for("/teams/:subdomain/activities/:id/edit", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/edit"

  defp path_for("/teams/:subdomain/activities/:id/attendance", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/attendance"

  defp path_for("/teams/:subdomain/activities/:id/history", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/history"

  defp path_for("/teams/:subdomain/activities/:id/mileage", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/mileage"

  defp path_for("/teams/:subdomain/activities/:id/take-attendance", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/take-attendance"

  defp path_for("/teams/:subdomain/members/:id", s, o), do: ~p"/teams/#{s}/members/#{o.member.id}"

  defp path_for("/teams/:subdomain/members/:id/groups", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/groups"

  defp path_for("/teams/:subdomain/members/:id/qualifications", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/qualifications"

  defp path_for("/teams/:subdomain/members/:id/card", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/card"

  defp path_for("/teams/:subdomain/members/:id/history", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/history"

  defp path_for("/teams/:subdomain/members/:id/card/apple-wallet", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/card/apple-wallet"

  defp path_for("/teams/:subdomain/members/:id/card/google-wallet", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/card/google-wallet"

  defp path_for("/teams/:subdomain/members/:id/image", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/image"

  defp path_for("/teams/:subdomain/groups/:id", s, o), do: ~p"/teams/#{s}/groups/#{o.group.id}"

  defp path_for("/teams/:subdomain/groups/:id/review", s, o),
    do: ~p"/teams/#{s}/groups/#{o.group.id}/review"

  defp path_for("/teams/:subdomain/proposed-changes/:id", s, o),
    do: ~p"/teams/#{s}/proposed-changes/#{o.change_set.id}"

  defp path_for("/teams/:subdomain/qualifications/:id", s, o),
    do: ~p"/teams/#{s}/qualifications/#{o.qualification.id}"

  defp path_for("/teams/:subdomain/tax-credit-letters/:id", s, o),
    do: ~p"/teams/#{s}/tax-credit-letters/#{o.letter.id}"

  defp path_for("/teams/:subdomain/tax-credit-letters/:id/pdf", s, o),
    do: ~p"/teams/#{s}/tax-credit-letters/#{o.letter.id}/pdf"
end

defmodule Web.TeamScopingTest do
  # A user on one team puts another team's record id in their own team's URL.
  # Every page must 404 before it reads the record, calls D4H, or calls Mapbox.
  use Web.ConnCase

  import App.DataFixtures

  @templates [
    "/:subdomain/activities/:id",
    "/:subdomain/activities/:id/attendance",
    "/:subdomain/activities/:id/mileage",
    "/:subdomain/members/:id",
    "/:subdomain/members/:id/groups",
    "/:subdomain/members/:id/qualifications",
    "/:subdomain/members/:id/image",
    "/:subdomain/groups/:id",
    "/:subdomain/groups/:id/review",
    "/:subdomain/qualifications/:id",
    "/:subdomain/tax-credit-letters/:id",
    "/:subdomain/tax-credit-letters/:id/pdf"
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
      letter: tax_credit_letter_fixture(member)
    }

    %{conn: log_in_user(conn, user), team: team, other: other}
  end

  test "every team route with an id is covered here" do
    routed =
      Web.Router.__routes__()
      |> Enum.map(& &1.path)
      |> Enum.filter(&(String.starts_with?(&1, "/:subdomain/") and &1 =~ "/:id"))
      |> MapSet.new()

    assert MapSet.new(@templates) == routed
  end

  for template <- @templates do
    test "#{template} 404s for another team's record", %{conn: conn, team: team, other: other} do
      path = path_for(unquote(template), team.subdomain, other)

      assert_error_sent 404, fn -> get(conn, path) end
    end
  end

  defp path_for("/:subdomain/activities/:id", s, o), do: ~p"/#{s}/activities/#{o.activity.id}"

  defp path_for("/:subdomain/activities/:id/attendance", s, o),
    do: ~p"/#{s}/activities/#{o.activity.id}/attendance"

  defp path_for("/:subdomain/activities/:id/mileage", s, o),
    do: ~p"/#{s}/activities/#{o.activity.id}/mileage"

  defp path_for("/:subdomain/members/:id", s, o), do: ~p"/#{s}/members/#{o.member.id}"

  defp path_for("/:subdomain/members/:id/groups", s, o),
    do: ~p"/#{s}/members/#{o.member.id}/groups"

  defp path_for("/:subdomain/members/:id/qualifications", s, o),
    do: ~p"/#{s}/members/#{o.member.id}/qualifications"

  defp path_for("/:subdomain/members/:id/image", s, o),
    do: ~p"/#{s}/members/#{o.member.id}/image"

  defp path_for("/:subdomain/groups/:id", s, o), do: ~p"/#{s}/groups/#{o.group.id}"

  defp path_for("/:subdomain/groups/:id/review", s, o),
    do: ~p"/#{s}/groups/#{o.group.id}/review"

  defp path_for("/:subdomain/qualifications/:id", s, o),
    do: ~p"/#{s}/qualifications/#{o.qualification.id}"

  defp path_for("/:subdomain/tax-credit-letters/:id", s, o),
    do: ~p"/#{s}/tax-credit-letters/#{o.letter.id}"

  defp path_for("/:subdomain/tax-credit-letters/:id/pdf", s, o),
    do: ~p"/#{s}/tax-credit-letters/#{o.letter.id}/pdf"
end

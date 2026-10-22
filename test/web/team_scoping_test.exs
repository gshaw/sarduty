defmodule Web.TeamScopingTest do
  # A user on one team puts another team's record id in their own team's URL.
  # Every page must 404 before it reads the record, calls D4H, or calls Mapbox.
  use Web.ConnCase

  import App.DataFixtures

  alias App.Model.ChangeSet

  @templates [
    "/teams/:subdomain/activities/:id",
    "/teams/:subdomain/activities/:id/edit",
    "/teams/:subdomain/activities/:id/history",
    "/teams/:subdomain/activities/:id/mileage",
    "/teams/:subdomain/activities/:id/take-attendance",
    "/teams/:subdomain/activities/:id/equipment",
    "/teams/:subdomain/activities/:id/templates",
    "/teams/:subdomain/activities/:id/tags",
    "/teams/:subdomain/equipment/:id",
    "/teams/:subdomain/equipment/:id/edit",
    "/teams/:subdomain/templates/:id",
    "/teams/:subdomain/endorsements/:id",
    "/teams/:subdomain/members/:id",
    "/teams/:subdomain/members/:id/edit",
    "/teams/:subdomain/members/:id/groups",
    "/teams/:subdomain/members/:id/qualifications",
    "/teams/:subdomain/members/:id/card",
    "/teams/:subdomain/members/:id/history",
    "/teams/:subdomain/members/:id/standing",
    "/teams/:subdomain/members/:id/card/apple-wallet",
    "/teams/:subdomain/members/:id/card/google-wallet",
    "/teams/:subdomain/members/:id/image",
    # View as member (#425), a POST.
    "/teams/:subdomain/members/:id/view-as",
    "/teams/:subdomain/groups/:id",
    "/teams/:subdomain/groups/:id/edit",
    "/teams/:subdomain/groups/:id/review",
    "/teams/:subdomain/groups/:id/rules/:rule_id",
    "/teams/:subdomain/proposed-changes/:id",
    "/teams/:subdomain/qualifications/:id",
    "/teams/:subdomain/qualifications/:id/edit",
    "/teams/:subdomain/tax-credit-letters/:id",
    "/teams/:subdomain/tax-credit-letters/:id/pdf",
    # A member's own letter (#156). Web.MeLiveTest covers another member on the same team.
    "/teams/:subdomain/me/tax-credit-letters/:id/pdf",
    # Add to calendar (#406). Web.ActivityLiveTest covers an incident a member can't see.
    "/teams/:subdomain/activities/:id/calendar"
  ]

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    other_team = team_fixture()
    member = member_fixture(other_team)
    group = group_fixture(other_team)
    endorsement = endorsement_fixture(other_team)

    other = %{
      activity: activity_fixture(other_team),
      member: member,
      group: group,
      rule: group_rule_fixture(group, endorsement),
      qualification: qualification_fixture(other_team),
      item: equipment_item_fixture(other_team),
      template: template_fixture(other_team),
      endorsement: endorsement,
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

      assert_error_sent 404, fn -> request(conn, unquote(template), path) end
    end
  end

  defp request(conn, "/teams/:subdomain/members/:id/view-as", path), do: post(conn, path)
  defp request(conn, _template, path), do: get(conn, path)

  describe "a member who is not a team admin" do
    # Public or bearer-token routes under /teams/:subdomain, outside the team pages.
    @public ["/teams/:subdomain/logo", "/teams/:subdomain/mcp"]

    setup %{conn: conn} do
      %{team: team, user: user} = member_with_login_fixture()
      %{conn: log_in_user(conn, user), member_team: team}
    end

    test "gets a 404 from every team route not listed in Web.RouterTest", %{
      conn: conn,
      member_team: team
    } do
      templates =
        for %{verb: :get, path: "/teams/:subdomain" <> _rest = path} <- Web.Router.__routes__(),
            path not in @public,
            path not in Web.RouterTest.member_route_paths(),
            uniq: true,
            do: path

      assert length(templates) > 40

      for template <- templates do
        path = template |> String.replace(":subdomain", team.subdomain) |> fill_ids()
        assert_error_sent 404, fn -> get(conn, path) end
      end
    end
  end

  # Any id: the team hook refuses before the page reads one.
  defp fill_ids(path), do: Regex.replace(~r/:[a-z_]+/, path, "1")

  defp path_for("/teams/:subdomain/members/:id/view-as", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/view-as"

  defp path_for("/teams/:subdomain/members/:id/edit", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/edit"

  defp path_for("/teams/:subdomain/groups/:id/rules/:rule_id", s, o),
    do: ~p"/teams/#{s}/groups/#{o.group.id}/rules/#{o.rule.id}"

  defp path_for("/teams/:subdomain/groups/:id/edit", s, o),
    do: ~p"/teams/#{s}/groups/#{o.group.id}/edit"

  defp path_for("/teams/:subdomain/qualifications/:id/edit", s, o),
    do: ~p"/teams/#{s}/qualifications/#{o.qualification.id}/edit"

  defp path_for("/teams/:subdomain/activities/:id", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}"

  defp path_for("/teams/:subdomain/activities/:id/edit", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/edit"

  defp path_for("/teams/:subdomain/activities/:id/history", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/history"

  defp path_for("/teams/:subdomain/activities/:id/mileage", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/mileage"

  defp path_for("/teams/:subdomain/activities/:id/take-attendance", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/take-attendance"

  defp path_for("/teams/:subdomain/activities/:id/equipment", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/equipment"

  defp path_for("/teams/:subdomain/activities/:id/templates", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/templates"

  defp path_for("/teams/:subdomain/activities/:id/tags", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/tags"

  defp path_for("/teams/:subdomain/equipment/:id", s, o),
    do: ~p"/teams/#{s}/equipment/#{o.item.id}"

  defp path_for("/teams/:subdomain/equipment/:id/edit", s, o),
    do: ~p"/teams/#{s}/equipment/#{o.item.id}/edit"

  defp path_for("/teams/:subdomain/endorsements/:id", s, o),
    do: ~p"/teams/#{s}/endorsements/#{o.endorsement.id}"

  defp path_for("/teams/:subdomain/templates/:id", s, o),
    do: ~p"/teams/#{s}/templates/#{o.template.id}"

  defp path_for("/teams/:subdomain/members/:id", s, o), do: ~p"/teams/#{s}/members/#{o.member.id}"

  defp path_for("/teams/:subdomain/members/:id/groups", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/groups"

  defp path_for("/teams/:subdomain/members/:id/qualifications", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/qualifications"

  defp path_for("/teams/:subdomain/members/:id/card", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/card"

  defp path_for("/teams/:subdomain/members/:id/history", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/history"

  defp path_for("/teams/:subdomain/members/:id/standing", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/standing"

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

  defp path_for("/teams/:subdomain/activities/:id/calendar", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/calendar"

  defp path_for("/teams/:subdomain/me/tax-credit-letters/:id/pdf", s, o),
    do: ~p"/teams/#{s}/me/tax-credit-letters/#{o.letter.id}/pdf"

  defp path_for("/teams/:subdomain/tax-credit-letters/:id/pdf", s, o),
    do: ~p"/teams/#{s}/tax-credit-letters/#{o.letter.id}/pdf"
end

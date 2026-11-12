defmodule Web.TeamScopingTest do
  # A user on one team puts another team's record id in their own team's URL.
  # Every page must 404 before it reads the record, calls D4H, or calls Mapbox.
  use Web.ConnCase

  import App.DataFixtures

  alias App.Model.OutboxMessage
  alias App.Repo

  @templates [
    "/teams/:subdomain/activities/:id",
    "/teams/:subdomain/activities/:id/edit",
    "/teams/:subdomain/activities/:id/history",
    "/teams/:subdomain/activities/:id/travel",
    "/teams/:subdomain/activities/:id/members",
    "/teams/:subdomain/activities/:id/attendance",
    "/teams/:subdomain/activities/:id/take-attendance",
    "/teams/:subdomain/activities/:id/equipment",
    "/teams/:subdomain/activities/:id/fields",
    "/teams/:subdomain/activities/:id/fields/edit",
    "/teams/:subdomain/activities/:id/equipment/add",
    "/teams/:subdomain/activities/:id/templates",
    "/teams/:subdomain/activities/:id/members/add",
    "/teams/:subdomain/activities/:id/members/remove",
    "/teams/:subdomain/activities/:id/members/ask",
    "/teams/:subdomain/activities/:id/members/update",
    "/teams/:subdomain/activities/:id/tags",
    # An organization's form on an activity (#950): the activity is found through the
    # team first. Web.ActivityOrgFormLiveTest covers a form that's off.
    "/teams/:subdomain/activities/:id/forms",
    "/teams/:subdomain/activities/:id/forms/:form_id",
    "/teams/:subdomain/activities/:id/forms/:form_id/pdf",
    "/teams/:subdomain/activities/:id/forms/:form_id/publish",
    "/teams/:subdomain/activities/:id/forms/:form_id/sign",
    "/teams/:subdomain/equipment/:id",
    "/teams/:subdomain/equipment/:id/fields",
    "/teams/:subdomain/equipment/:id/fields/edit",
    "/teams/:subdomain/equipment/:id/edit",
    "/teams/:subdomain/equipment/:id/history",
    "/teams/:subdomain/templates/:id",
    "/teams/:subdomain/templates/:id/edit",
    "/teams/:subdomain/templates/:id/items/edit",
    "/teams/:subdomain/templates/:id/tags/edit",
    "/teams/:subdomain/templates/:id/groups/edit",
    "/teams/:subdomain/templates/:id/fields/edit",
    # Chore pages need member logins, which this team lacks. Web.ChoreLiveTest,
    # Web.ChoreCollectionLiveTest, and Web.Settings.ChoreCategoryLiveTest cover another team's
    # records with them on.
    "/teams/:subdomain/settings/chore-categories/:id",
    "/teams/:subdomain/chores/:id",
    "/teams/:subdomain/chores/:id/edit",
    "/teams/:subdomain/whiteboard/:id/edit",
    # Places change here only on a SAR Duty Records team, which this team isn't.
    # Web.Settings.PlaceLiveTest covers another Records team's place.
    "/teams/:subdomain/settings/places/:id",
    # Certificates (#493): this team has them on, so these find the record through it.
    "/teams/:subdomain/certificates/:id",
    "/teams/:subdomain/certificates/:id/file",
    # A member's own certificate. Web.CertificateFormLiveTest covers another member's.
    "/teams/:subdomain/certificates/:id/edit",
    # A photo a member added (#1029): this team has Photos on, so these find the record
    # through it.
    "/teams/:subdomain/photos/members/:id",
    "/teams/:subdomain/photos/members/:id/file",
    # An activity's photos (#1032), on another team's exercise, which takes photos, and
    # its accepted photo, which anyone on its own team sees.
    "/teams/:subdomain/activities/:id/photos",
    "/teams/:subdomain/activities/:id/photos/new",
    "/teams/:subdomain/activities/:id/photos/ask",
    "/teams/:subdomain/photos/:id/file",
    # That accepted photo's page (#1033), Edit photo (#1032, part 8), and Export for a
    # post with its JPEG (part 9).
    "/teams/:subdomain/photos/:id",
    "/teams/:subdomain/photos/:id/edit",
    "/teams/:subdomain/photos/:id/export",
    "/teams/:subdomain/photos/:id/export/file",
    "/teams/:subdomain/endorsements/:id",
    "/teams/:subdomain/members/:id",
    "/teams/:subdomain/members/:id/edit",
    "/teams/:subdomain/members/:id/groups",
    "/teams/:subdomain/members/:id/equipment",
    "/teams/:subdomain/members/:id/qualifications",
    "/teams/:subdomain/members/:id/card",
    "/teams/:subdomain/members/:id/history",
    "/teams/:subdomain/members/:id/fields",
    "/teams/:subdomain/members/:id/fields/edit",
    "/teams/:subdomain/members/:id/standing",
    "/teams/:subdomain/members/:id/image",
    "/teams/:subdomain/members/:id/certificates/:award_id",
    # View as member (#425), a POST.
    "/teams/:subdomain/members/:id/view-as",
    "/teams/:subdomain/groups/:id",
    "/teams/:subdomain/groups/:id/edit",
    "/teams/:subdomain/groups/:id/review",
    "/teams/:subdomain/groups/:id/rules/:rule_id",
    "/teams/:subdomain/qualifications/:id",
    "/teams/:subdomain/qualifications/:id/edit",
    # A member's letter for a year (#970): the member is found through the team.
    "/teams/:subdomain/tax-credit-letters/:year/members/:id",
    "/teams/:subdomain/tax-credit-letters/:year/members/:id/draft.png",
    "/teams/:subdomain/pdfs/:id",
    "/teams/:subdomain/pdfs/:id/preview.png",
    # A member's own letter (#156). Web.MeLiveTest covers another member on the same team.
    "/teams/:subdomain/me/tax-credit-letters/:id/pdf",
    "/teams/:subdomain/me/qualifications/:id/certificate",
    # Add to calendar (#406). Web.ActivityLiveTest covers an incident a member can't see.
    "/teams/:subdomain/activities/:id/calendar",
    # A team's own report (#768). A built-in one's id is its slug, the same on every team.
    "/teams/:subdomain/reports/:id",
    "/teams/:subdomain/reports/:id/edit",
    "/teams/:subdomain/reports/:id/history",
    "/teams/:subdomain/reports/:id/csv",
    # Only a demo team has an Outbox, and this team isn't one. Web.DemoFlowTest covers
    # another demo's message.
    "/teams/:subdomain/outbox/:id",
    "/teams/:subdomain/outbox/:id/attachments/:attachment_id"
  ]

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    team =
      team
      |> Ecto.Changeset.change(
        member_logins: true,
        certificates_enabled: true,
        photos_enabled: true
      )
      |> Repo.update!()

    other_team = team_fixture(%{photos_enabled: true})
    member = member_fixture(other_team)
    group = group_fixture(other_team)
    endorsement = endorsement_fixture(other_team)
    exercise = activity_fixture(other_team)

    organization = organization_fixture([other_team])

    other = %{
      activity: activity_fixture(other_team, %{activity_kind: "incident"}),
      form: form_fixture(organization, %{state: :on}),
      member: member,
      group: group,
      rule: group_rule_fixture(group, endorsement),
      qualification: qualification_fixture(other_team),
      item: equipment_item_fixture(other_team),
      template: template_fixture(other_team),
      chore_category: chore_category_fixture(other_team),
      chore: chore_fixture(member, chore_category_fixture(other_team)),
      endorsement: endorsement,
      whiteboard_note: whiteboard_note_fixture(other_team),
      place: location_bookmark_fixture(other_team),
      letter: tax_credit_letter_fixture(member),
      award: certificate_award_fixture(other_team, member),
      outbox: OutboxMessage.add_text!("+16045551234", "Theirs"),
      certificate: certificate_fixture(member, qualification_fixture(other_team)),
      photo: member_photo_fixture(member),
      exercise: exercise,
      activity_photo: activity_photo_fixture(exercise, %{status: :accepted}),
      report:
        Repo.insert!(%App.Model.SavedReport{
          team_id: other_team.id,
          name: "Theirs",
          query: "select title from groups"
        })
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

  defp request(conn, "/teams/:subdomain/activities/:id/forms/:form_id/pdf", path),
    do: post(conn, path)

  defp request(conn, _template, path), do: get(conn, path)

  describe "a member who is not a team admin" do
    # Public or bearer-token routes under /teams/:subdomain, outside the team pages, and
    # the Allow page, which tells a member who may connect an agent (#761).
    @public [
      "/teams/:subdomain/logo",
      "/teams/:subdomain/mcp",
      "/teams/:subdomain/oauth/authorize"
    ]

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

  defp path_for("/teams/:subdomain/members/:id/certificates/:award_id", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/certificates/#{o.award.id}"

  defp path_for("/teams/:subdomain/me/qualifications/:id/certificate", s, o),
    do: ~p"/teams/#{s}/me/qualifications/#{o.award.id}/certificate"

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

  defp path_for("/teams/:subdomain/activities/:id/forms", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/forms"

  defp path_for("/teams/:subdomain/activities/:id/forms/:form_id", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/forms/#{o.form.id}"

  defp path_for("/teams/:subdomain/activities/:id/forms/:form_id/publish", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/forms/#{o.form.id}/publish"

  defp path_for("/teams/:subdomain/activities/:id/forms/:form_id/sign", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/forms/#{o.form.id}/sign"

  defp path_for("/teams/:subdomain/activities/:id/forms/:form_id/pdf", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/forms/#{o.form.id}/pdf"

  defp path_for("/teams/:subdomain/activities/:id/edit", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/edit"

  defp path_for("/teams/:subdomain/activities/:id/history", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/history"

  defp path_for("/teams/:subdomain/activities/:id/members", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/members"

  defp path_for("/teams/:subdomain/activities/:id/travel", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/travel"

  defp path_for("/teams/:subdomain/activities/:id/attendance", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/attendance"

  defp path_for("/teams/:subdomain/activities/:id/take-attendance", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/take-attendance"

  defp path_for("/teams/:subdomain/activities/:id/equipment", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/equipment"

  defp path_for("/teams/:subdomain/activities/:id/fields", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/fields"

  defp path_for("/teams/:subdomain/activities/:id/fields/edit", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/fields/edit"

  defp path_for("/teams/:subdomain/activities/:id/equipment/add", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/equipment/add"

  defp path_for("/teams/:subdomain/activities/:id/templates", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/templates"

  defp path_for("/teams/:subdomain/activities/:id/members/add", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/members/add"

  defp path_for("/teams/:subdomain/activities/:id/members/remove", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/members/remove"

  defp path_for("/teams/:subdomain/activities/:id/members/ask", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/members/ask"

  defp path_for("/teams/:subdomain/activities/:id/members/update", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/members/update"

  defp path_for("/teams/:subdomain/activities/:id/tags", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/tags"

  defp path_for("/teams/:subdomain/equipment/:id", s, o),
    do: ~p"/teams/#{s}/equipment/#{o.item.id}"

  defp path_for("/teams/:subdomain/equipment/:id/fields", s, o),
    do: ~p"/teams/#{s}/equipment/#{o.item.id}/fields"

  defp path_for("/teams/:subdomain/equipment/:id/fields/edit", s, o),
    do: ~p"/teams/#{s}/equipment/#{o.item.id}/fields/edit"

  defp path_for("/teams/:subdomain/equipment/:id/edit", s, o),
    do: ~p"/teams/#{s}/equipment/#{o.item.id}/edit"

  defp path_for("/teams/:subdomain/equipment/:id/history", s, o),
    do: ~p"/teams/#{s}/equipment/#{o.item.id}/history"

  defp path_for("/teams/:subdomain/endorsements/:id", s, o),
    do: ~p"/teams/#{s}/endorsements/#{o.endorsement.id}"

  defp path_for("/teams/:subdomain/templates/:id", s, o),
    do: ~p"/teams/#{s}/templates/#{o.template.id}"

  defp path_for("/teams/:subdomain/templates/:id/edit", s, o),
    do: ~p"/teams/#{s}/templates/#{o.template.id}/edit"

  defp path_for("/teams/:subdomain/templates/:id/items/edit", s, o),
    do: ~p"/teams/#{s}/templates/#{o.template.id}/items/edit"

  defp path_for("/teams/:subdomain/templates/:id/tags/edit", s, o),
    do: ~p"/teams/#{s}/templates/#{o.template.id}/tags/edit"

  defp path_for("/teams/:subdomain/templates/:id/groups/edit", s, o),
    do: ~p"/teams/#{s}/templates/#{o.template.id}/groups/edit"

  defp path_for("/teams/:subdomain/templates/:id/fields/edit", s, o),
    do: ~p"/teams/#{s}/templates/#{o.template.id}/fields/edit"

  defp path_for("/teams/:subdomain/settings/chore-categories/:id", s, o),
    do: ~p"/teams/#{s}/settings/chore-categories/#{o.chore_category.id}"

  defp path_for("/teams/:subdomain/settings/places/:id", s, o),
    do: ~p"/teams/#{s}/settings/places/#{o.place.id}"

  defp path_for("/teams/:subdomain/chores/:id", s, o), do: ~p"/teams/#{s}/chores/#{o.chore.id}"

  defp path_for("/teams/:subdomain/chores/:id/edit", s, o),
    do: ~p"/teams/#{s}/chores/#{o.chore.id}/edit"

  defp path_for("/teams/:subdomain/certificates/:id", s, o),
    do: ~p"/teams/#{s}/certificates/#{o.certificate.id}"

  defp path_for("/teams/:subdomain/certificates/:id/file", s, o),
    do: ~p"/teams/#{s}/certificates/#{o.certificate.id}/file"

  defp path_for("/teams/:subdomain/certificates/:id/edit", s, o),
    do: ~p"/teams/#{s}/certificates/#{o.certificate.id}/edit"

  defp path_for("/teams/:subdomain/photos/members/:id", s, o),
    do: ~p"/teams/#{s}/photos/members/#{o.photo.id}"

  defp path_for("/teams/:subdomain/photos/members/:id/file", s, o),
    do: ~p"/teams/#{s}/photos/members/#{o.photo.id}/file"

  defp path_for("/teams/:subdomain/activities/:id/photos", s, o),
    do: ~p"/teams/#{s}/activities/#{o.exercise.id}/photos"

  defp path_for("/teams/:subdomain/activities/:id/photos/new", s, o),
    do: ~p"/teams/#{s}/activities/#{o.exercise.id}/photos/new"

  defp path_for("/teams/:subdomain/activities/:id/photos/ask", s, o),
    do: ~p"/teams/#{s}/activities/#{o.exercise.id}/photos/ask"

  defp path_for("/teams/:subdomain/photos/:id/file", s, o),
    do: ~p"/teams/#{s}/photos/#{o.activity_photo.id}/file"

  defp path_for("/teams/:subdomain/photos/:id", s, o),
    do: ~p"/teams/#{s}/photos/#{o.activity_photo.id}"

  defp path_for("/teams/:subdomain/photos/:id/edit", s, o),
    do: ~p"/teams/#{s}/photos/#{o.activity_photo.id}/edit"

  defp path_for("/teams/:subdomain/photos/:id/export", s, o),
    do: ~p"/teams/#{s}/photos/#{o.activity_photo.id}/export"

  defp path_for("/teams/:subdomain/photos/:id/export/file", s, o),
    do: ~p"/teams/#{s}/photos/#{o.activity_photo.id}/export/file"

  defp path_for("/teams/:subdomain/members/:id", s, o), do: ~p"/teams/#{s}/members/#{o.member.id}"

  defp path_for("/teams/:subdomain/members/:id/groups", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/groups"

  defp path_for("/teams/:subdomain/members/:id/equipment", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/equipment"

  defp path_for("/teams/:subdomain/members/:id/qualifications", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/qualifications"

  defp path_for("/teams/:subdomain/members/:id/card", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/card"

  defp path_for("/teams/:subdomain/members/:id/history", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/history"

  defp path_for("/teams/:subdomain/members/:id/fields", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/fields"

  defp path_for("/teams/:subdomain/members/:id/fields/edit", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/fields/edit"

  defp path_for("/teams/:subdomain/members/:id/standing", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/standing"

  defp path_for("/teams/:subdomain/members/:id/image", s, o),
    do: ~p"/teams/#{s}/members/#{o.member.id}/image"

  defp path_for("/teams/:subdomain/groups/:id", s, o), do: ~p"/teams/#{s}/groups/#{o.group.id}"

  defp path_for("/teams/:subdomain/groups/:id/review", s, o),
    do: ~p"/teams/#{s}/groups/#{o.group.id}/review"

  defp path_for("/teams/:subdomain/qualifications/:id", s, o),
    do: ~p"/teams/#{s}/qualifications/#{o.qualification.id}"

  defp path_for("/teams/:subdomain/tax-credit-letters/:year/members/:id" <> rest, s, o),
    do: "/teams/#{s}/tax-credit-letters/#{o.letter.year}/members/#{o.member.id}#{rest}"

  defp path_for("/teams/:subdomain/activities/:id/calendar", s, o),
    do: ~p"/teams/#{s}/activities/#{o.activity.id}/calendar"

  defp path_for("/teams/:subdomain/me/tax-credit-letters/:id/pdf", s, o),
    do: ~p"/teams/#{s}/me/tax-credit-letters/#{o.letter.id}/pdf"

  defp path_for("/teams/:subdomain/pdfs/:id", s, o),
    do: ~p"/teams/#{s}/pdfs/#{o.letter.id}"

  defp path_for("/teams/:subdomain/pdfs/:id/preview.png", s, o),
    do: ~p"/teams/#{s}/pdfs/#{o.letter.id}/preview.png"

  defp path_for("/teams/:subdomain/whiteboard/:id/edit", s, o),
    do: ~p"/teams/#{s}/whiteboard/#{o.whiteboard_note.id}/edit"

  defp path_for("/teams/:subdomain/outbox/:id/attachments/:attachment_id", s, o),
    do: "/teams/#{s}/outbox/#{o.outbox.id}/attachments/1"

  defp path_for("/teams/:subdomain/outbox/:id" <> rest, s, o),
    do: "/teams/#{s}/outbox/#{o.outbox.id}#{rest}"

  defp path_for("/teams/:subdomain/reports/:id" <> rest, s, o),
    do: "/teams/#{s}/reports/#{o.report.id}#{rest}"
end

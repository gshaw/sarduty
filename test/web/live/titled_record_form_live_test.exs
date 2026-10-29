defmodule Web.TitledRecordFormLiveTest do
  # Qualifications and groups of a team on SAR Duty Records (docs/records.md), and a
  # member's awards and groups on their tabs. A D4H team gets the group pages (#546).
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSetRow
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRule
  alias App.Operation.SaveTitledRecord
  alias App.RecordsStub
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
    member = Repo.get_by!(App.Model.Member, team_id: team.id, email: user.email)
    %{conn: log_in_user(conn, user), team: team, member: member}
  end

  defp stub, do: RecordsStub.stub(&reply/3)

  defp reply("POST", "/member-qualification-awards", _body) do
    {200,
     %{
       "id" => 300,
       "member" => %{"resourceType" => "Member", "id" => 1},
       "qualification" => %{"id" => 1},
       "startsAt" => "2026-05-01T07:00:00Z"
     }}
  end

  defp reply("POST", "/documents", _body),
    do: {200, %{"id" => 1_000_001, "targetResource" => %{"id" => 300}}}

  defp reply("POST", "/member-group-memberships", _body) do
    {200,
     %{
       "id" => 400,
       "member" => %{"resourceType" => "Member", "id" => 1},
       "group" => %{"id" => 1}
     }}
  end

  defp reply(_method, _path, body) do
    {200, Map.merge(%{"id" => 99, "title" => "Rope Team"}, body || %{})}
  end

  defp add(conn, team, path, title) do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/#{path}/new")
    lv |> form("#titled-record-form", form: %{title: title}) |> render_submit()
  end

  test "a qualification is added, renamed, and deleted", %{conn: conn, team: team} do
    stub()
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/qualifications")
    assert has_element?(list, "#qualification-add")

    add(conn, team, "qualifications", "Swiftwater Rescue")

    assert_received {:records, "POST", "/member-qualifications",
                     %{"title" => "Swiftwater Rescue"}}

    qualification = qualification_fixture(team, %{title: "Swiftwater", d4h_qualification_id: 99})
    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}")
    assert has_element?(page, "#qualification-actions #qualification-edit", "Rename")
    assert has_element?(page, "#qualification-actions #qualification-delete", "Delete")

    # Rename is a page; Delete opens the confirm dialog on the record's page (docs/urls.md).
    {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}/edit")
    assert has_element?(edit, "h1", "Rename Swiftwater")

    assert has_element?(
             edit,
             ~s|#titled-record-cancel[href="#{~p"/teams/#{team}/qualifications/#{qualification.id}"}"]|
           )

    edit |> form("#titled-record-form", form: %{title: "Swiftwater Rescue 2"}) |> render_submit()

    assert_received {:records, "PATCH", "/member-qualifications/99",
                     %{"title" => "Swiftwater Rescue 2"}}

    page |> element("#qualification-delete") |> render_click()
    assert_received {:records, "DELETE", "/member-qualifications/99", nil}
  end

  test "the organization's qualification can't be renamed or deleted (#652)",
       %{conn: conn, team: team} do
    qualification = qualification_fixture(team, %{title: "GSAR", organization_owned: true})
    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}")
    refute has_element?(page, "#qualification-edit")

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}/edit")
    end
  end

  test "a qualification is awarded on a member's tab, and removed",
       %{conn: conn, team: team, member: member} do
    stub()
    qualification = qualification_fixture(team, %{d4h_qualification_id: 99})

    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")

    tab
    |> form("#award-form",
      award: %{qualification_id: qualification.id, starts_on: "2026-05-01", ends_on: "2029-05-01"}
    )
    |> render_submit()

    assert_received {:records, "POST", "/member-qualification-awards", body}

    assert body == %{
             "qualificationId" => 99,
             "memberId" => member.d4h_member_id,
             "startsAt" => "2026-05-01T07:00:00Z",
             "endsAt" => "2029-05-01T07:00:00Z"
           }

    award = qualification_award_fixture(qualification, member)
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")
    tab |> element("#remove-award-#{award.id}") |> render_click()

    path = "/member-qualification-awards/#{award.d4h_award_id}"
    assert_received {:records, "DELETE", ^path, nil}
  end

  test "an award takes a certificate, uploaded once the award is in (#493)",
       %{conn: conn, team: team, member: member} do
    stub()
    qualification = qualification_fixture(team, %{d4h_qualification_id: 99})
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")

    tab
    |> file_input("#award-form", :certificate, [
      %{name: "first-aid.pdf", content: "%PDF-1.7 certificate", type: "application/pdf"}
    ])
    |> render_upload("first-aid.pdf")

    tab
    |> form("#award-form", award: %{qualification_id: qualification.id, starts_on: "2026-05-01"})
    |> render_submit()

    assert_received {:records, "POST", "/member-qualification-awards", _award}
    assert_received {:records, "POST", "/documents", {:multipart, body}}
    assert body =~ ~s(name="targetResourceId"\r\n\r\n300)
    assert body =~ "%PDF-1.7 certificate"
  end

  # Records takes the award and refuses its certificate.
  defp refuse_upload("POST", "/documents", _body),
    do: {422, %{"title" => "Records refused the file"}}

  defp refuse_upload(method, path, body), do: reply(method, path, body)

  test "an award whose certificate does not upload starts the form over, with why",
       %{conn: conn, team: team, member: member} do
    RecordsStub.stub(&refuse_upload/3)

    qualification = qualification_fixture(team, %{title: "First Aid", d4h_qualification_id: 99})
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")

    tab
    |> file_input("#award-form", :certificate, [
      %{name: "first-aid.pdf", content: "%PDF-1.7 certificate", type: "application/pdf"}
    ])
    |> render_upload("first-aid.pdf")

    start = ~s(#award-form input[name="award[starts_on]"][value="2026-05-01"])

    filled =
      form(tab, "#award-form",
        award: %{qualification_id: qualification.id, starts_on: "2026-05-01"}
      )

    render_change(filled)
    assert has_element?(tab, start)

    assert render_submit(filled) =~ "First Aid is awarded, but its certificate did not upload."
    refute has_element?(tab, start)
  end

  test "an award needs a qualification and a start, listed in the summary",
       %{conn: conn, team: team, member: member} do
    qualification_fixture(team)
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")
    tab |> form("#award-form", award: %{starts_on: ""}) |> render_submit()

    assert has_element?(tab, "#award-form .error-summary", "Select a qualification.")
    assert has_element?(tab, "#award-form .error-summary", "Enter the day it starts.")
  end

  test "a group is added, joined, left, and deleted, its copy written each time",
       %{conn: conn, team: team, member: member} do
    stub()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/groups/new")
    assert has_element?(lv, ~s|#titled-record-cancel[href="#{~p"/teams/#{team}/groups"}"]|)
    lv |> form("#titled-record-form", form: %{title: "Rope Team"}) |> render_submit()
    assert_received {:records, "POST", "/member-groups", %{"title" => "Rope Team"}}

    group = Repo.get_by!(Group, team_id: team.id, d4h_group_id: 99)
    assert %{title: "Rope Team", organization_owned: false} = group
    assert_redirect(lv, ~p"/teams/#{team}/groups/#{group.id}")

    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/groups")
    tab |> form("#add-group-form", %{group_id: group.id}) |> render_submit()

    assert_received {:records, "POST", "/member-group-memberships", body}
    assert body == %{"groupId" => 99, "memberId" => member.d4h_member_id}
    group_member = Repo.get_by!(GroupMember, group_id: group.id, member_id: member.id)
    assert group_member.d4h_group_membership_id == 400

    tab |> element("#remove-group-#{group_member.id}") |> render_click()
    assert_received {:records, "DELETE", "/member-group-memberships/400", nil}
    refute Repo.get(GroupMember, group_member.id)

    {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/groups/#{group.id}/edit")

    assert has_element?(
             edit,
             ~s|#titled-record-cancel[href="#{~p"/teams/#{team}/groups/#{group.id}"}"]|
           )

    edit |> form("#titled-record-form", form: %{title: "Rope Rescue"}) |> render_submit()
    assert_received {:records, "PATCH", "/member-groups/99", %{"title" => "Rope Rescue"}}
    assert Repo.get!(Group, group.id).title == "Rope Rescue"

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/groups/#{group.id}")
    page |> element("#group-delete") |> render_click()
    assert_received {:records, "DELETE", "/member-groups/99", nil}
    refute Repo.get(Group, group.id)
    refute_received {:records, "GET", _path, _body}
  end

  test "a group's title is refused when another group uses it, in any case",
       %{conn: conn, team: team} do
    group_fixture(team, %{title: "Aircraft", organization_owned: true})
    rope = group_fixture(team, %{title: "Rope Team"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/groups/new")
    lv |> form("#titled-record-form", form: %{title: "aircraft"}) |> render_submit()

    assert has_element?(
             lv,
             "#titled-record-form .error-summary",
             "Enter a title no other group uses."
           )

    refute_received {:records, _method, _path, _body}

    # Its own title in another case is a rename.
    stub()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/groups/#{rope.id}/edit")
    lv |> form("#titled-record-form", form: %{title: "Rope team"}) |> render_submit()
    assert_received {:records, "PATCH", _path, %{"title" => "Rope team"}}
  end

  test "deleting a group names what stops, and takes its own rules",
       %{conn: conn, team: team, member: member} do
    stub()
    ground = group_fixture(team, %{title: "Ground Search Team"})
    group_member_fixture(ground, member)
    group_rule_fixture(ground, group_fixture(team, %{title: "GSAR"}))
    callout = group_fixture(team, %{title: "Callout"})
    group_rule_fixture(callout, ground)
    template_fixture(team, "Truck 1", [], [], [ground])
    team |> Ecto.Changeset.change(watch_d4h_group_id: ground.d4h_group_id) |> Repo.update!()

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/groups/#{ground.id}")

    items = [
      "Its 1 member leaves it.",
      "Its rule is deleted.",
      "The rules of Callout stop working until you change them.",
      "The template Truck 1 stops adding its members.",
      "The attendance check stops until you select another group."
    ]

    # It takes a member with it, so the dialog asks for the box ticked (#651).
    button = page |> element("#group-delete") |> render()
    assert button =~ ~s(data-confirm="Delete the group Ground Search Team?")

    assert button
           |> Floki.parse_fragment!()
           |> Floki.attribute("data-confirm-list")
           |> hd()
           |> Jason.decode!() == items

    assert button =~ ~s(data-confirm-check="I understand 1 member and its rules are lost.")
    assert button =~ ~s(data-confirm-warning="SAR Duty Records can&#39;t bring it back.")

    page |> element("#group-delete") |> render_click()
    refute Repo.get(Group, ground.id)
    assert [%{d4h_group_id: d4h_group_id}] = GroupRule.get_all(team.id)
    assert d4h_group_id == callout.d4h_group_id

    # The delete row keeps who was in it and its rules, to rebuild it by hand.
    row = Repo.get_by!(ChangeSetRow, action: :delete_group, team_id: team.id)
    name = member.name

    assert %{"title" => "Ground Search Team", "members" => [^name], "rules" => ["In GSAR"]} =
             row.old_value
  end

  test "deleting a qualification someone holds asks for the box ticked",
       %{conn: conn, team: team, member: member} do
    qualification = qualification_fixture(team, %{title: "Swiftwater"})
    qualification_award_fixture(qualification, member)

    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}")
    link = page |> element("#qualification-delete") |> render()

    assert link =~ ~s(data-confirm-check="I understand 1 member loses it.")
    assert link =~ "1 member loses it."
  end

  test "deleting a group nobody is in asks a simple question", %{conn: conn, team: team} do
    empty = group_fixture(team, %{title: "Swiftwater"})
    {:ok, page, _html} = live(conn, ~p"/teams/#{team}/groups/#{empty.id}")
    link = page |> element("#group-delete") |> render()

    assert link =~ ~s(data-confirm="Delete Swiftwater? Nobody is in it.")
    assert link =~ ~s(data-confirm-button="Delete group")
    refute link =~ "data-confirm-check"
  end

  test "the organization's group is never renamed or deleted", %{team: team} do
    organization_fixture([team], %{short_name: "BCSARA"})
    team = Repo.reload!(team)
    group = group_fixture(team, %{title: "Aircraft", organization_owned: true})
    user = App.AccountsFixtures.user_fixture()
    now = DateTime.utc_now()
    text = "Only BCSARA can rename or delete it."

    assert {:error, ^text} =
             SaveTitledRecord.save(team, :group, group, %{"title" => "Planes"}, user, now)

    assert {:error, ^text} = SaveTitledRecord.delete(team, :group, group, user, now)
    refute_received {:records, _method, _path, _body}
  end

  test "a title is needed", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/groups/new")
    lv |> form("#titled-record-form", form: %{title: ""}) |> render_submit()
    assert has_element?(lv, "#titled-record-form .error-summary", "Enter a title.")
  end

  test "a D4H team changes its groups here, and its qualifications in D4H", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    conn = log_in_user(conn, user)
    member = member_fixture(team)
    qualification_fixture(team)
    group_fixture(team)

    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/qualifications")
    refute has_element?(list, "#qualification-add")
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/groups")
    assert has_element?(list, "#group-add")
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/qualifications")
    refute has_element?(tab, "#award-form")
    {:ok, tab, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/groups")
    assert has_element?(tab, "#add-group-form")

    assert {:ok, _lv, _html} = live(conn, ~p"/teams/#{team}/groups/new")
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/qualifications/new") end
  end
end

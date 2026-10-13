defmodule Web.GroupLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification

  # The crash tests below log the LiveView's exit.
  @moduletag :capture_log

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    group = group_fixture(team)
    qualification = qualification_fixture(team)
    endorsement = endorsement_fixture(team, %{name: "First Aid"})
    endorsement_qualification_fixture(endorsement, qualification)

    other_team = team_fixture()
    other_endorsement = endorsement_fixture(other_team)

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/groups/#{group.id}")

    %{
      team: team,
      group: group,
      conn: conn,
      path: ~p"/teams/#{team}/groups/#{group.id}",
      lv: lv,
      qualification: qualification,
      endorsement: endorsement,
      other_endorsement: other_endorsement
    }
  end

  test "adds and removes the team's endorsements, never another team's", ctx do
    render_submit(ctx.lv, "add-endorsement", %{"endorsement-id" => ctx.endorsement.id})
    assert [%{name: "First Aid"}] = Endorsement.get_all_for_group(ctx.group)

    render_click(ctx.lv, "remove-endorsement", %{"endorsement-id" => ctx.endorsement.id})
    assert [] = Endorsement.get_all_for_group(ctx.group)

    crash(ctx.lv, "add-endorsement", %{"endorsement-id" => ctx.other_endorsement.id})
    assert [] = Endorsement.get_all_for_group(ctx.group)
  end

  test "the editor lists the rule and links each endorsement", ctx do
    group_endorsement_fixture(ctx.group, ctx.endorsement)
    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    lv |> element("#edit-rules") |> render_click()

    assert has_element?(
             lv,
             ~s|#rule-#{ctx.endorsement.id} a[href="/teams/#{ctx.team.subdomain}/endorsements/#{ctx.endorsement.id}"]|
           )

    assert has_element?(lv, "#rule-#{ctx.endorsement.id}", ctx.qualification.title)
  end

  test "a rule naming a qualification deleted in D4H shows a warning instead of changes", ctx do
    group_endorsement_fixture(ctx.group, ctx.endorsement)

    EndorsementQualification.insert!(
      ctx.endorsement,
      System.unique_integer([:positive])
    )

    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(lv, "#rule-broken")
  end

  test "the rule reads by endorsement, and each removal says why", ctx do
    group_endorsement_fixture(ctx.group, ctx.endorsement)
    ended = member_fixture(ctx.team, %{name: "Alex Morgan"})
    qualification_award_fixture(ctx.qualification, ended, %{ends_at: ~U[2026-03-31 19:00:00Z]})
    group_member_fixture(ctx.group, ended)
    member = member_fixture(ctx.team, %{name: "Jordan Lee"})
    group_member_fixture(ctx.group, member)

    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(lv, "#rule-sentence", "Members must hold First Aid.")
    assert has_element?(lv, "#would-remove-#{ended.id}", "expired Mar 31, 2026")
    assert has_element?(lv, "#would-remove-#{member.id}", "No First Aid on record")
  end

  # A miss raises and takes the LiveView down, as a 404 would on a page load.
  defp crash(lv, event, params) do
    Process.flag(:trap_exit, true)
    assert {{%Ecto.NoResultsError{}, _stack}, _call} = catch_exit(render_click(lv, event, params))
  end
end

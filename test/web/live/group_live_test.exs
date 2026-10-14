defmodule Web.GroupLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.Model.GroupEndorsement
  alias App.Model.GroupParent
  alias App.Repo

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

  test "a group starts from another: its rule, never its hand-added members", ctx do
    gsar = group_fixture(ctx.team, %{title: "GSAR team"})
    group_endorsement_fixture(gsar, ctx.endorsement)
    sw1 = qualification_fixture(ctx.team)
    swiftwater = endorsement_fixture(ctx.team, %{name: "Swiftwater 1"})
    endorsement_qualification_fixture(swiftwater, sw1)
    group_endorsement_fixture(ctx.group, swiftwater)

    both = member_fixture(ctx.team, %{name: "Both"})
    qualification_award_fixture(ctx.qualification, both)
    qualification_award_fixture(sw1, both)
    by_hand = member_fixture(ctx.team, %{name: "By Hand"})
    qualification_award_fixture(sw1, by_hand)
    group_member_fixture(gsar, by_hand)

    {:ok, lv, _html} = live(ctx.conn, ctx.path)
    lv |> element("#edit-rules") |> render_click()
    lv |> form("#parent-form", %{"parent-id" => gsar.id}) |> render_change()

    assert has_element?(lv, "#parent-endorsements", "First Aid")
    lv |> element("#done-editing") |> render_click()
    assert has_element?(lv, "#rule-sentence", "Members of GSAR team who also hold Swiftwater 1")
    assert has_element?(lv, "#rule-parent-hint", "everyone who holds First Aid")
    assert has_element?(lv, "#would-add-#{both.id}")
    refute has_element?(lv, "#would-add-#{by_hand.id}")

    ruled = ctx.team.id |> GroupEndorsement.ruled_d4h_group_ids_query() |> Repo.all()
    assert ctx.group.d4h_group_id in ruled

    {:ok, gsar_lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/groups/#{gsar.id}")
    gsar_lv |> element("#edit-rules") |> render_click()
    refute has_element?(gsar_lv, "#parent-id option[value='#{ctx.group.id}']")
    render_change(gsar_lv, "set-parent", %{"parent-id" => ctx.group.id})

    assert GroupParent.parents_by_group(ctx.team.id) == %{
             ctx.group.d4h_group_id => gsar.d4h_group_id
           }

    render_change(lv, "set-parent", %{"parent-id" => ""})
    assert GroupParent.parents_by_group(ctx.team.id) == %{}
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

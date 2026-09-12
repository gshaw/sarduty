defmodule Web.GroupLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.GroupRuleClause
  alias App.Model.GroupRuleClauseQualification
  alias App.Repo

  # The crash tests below log the LiveView's exit.
  @moduletag :capture_log

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    group = group_fixture(team)
    qualification = qualification_fixture(team)
    clause = group_rule_clause_fixture(group)

    other_team = team_fixture()
    other_clause = other_team |> group_fixture() |> group_rule_clause_fixture()

    other_clause_qualification =
      group_rule_clause_qualification_fixture(other_clause, qualification_fixture(other_team))

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/groups/#{group.id}")

    %{
      conn: conn,
      path: ~p"/#{team.subdomain}/groups/#{group.id}",
      lv: lv,
      qualification: qualification,
      clause: clause,
      other_clause: other_clause,
      other_clause_qualification: other_clause_qualification
    }
  end

  test "delete-clause deletes this group's clause but not another team's", ctx do
    render_click(ctx.lv, "delete-clause", %{"clause-id" => ctx.clause.id})
    refute Repo.get(GroupRuleClause, ctx.clause.id)

    crash(ctx.lv, "delete-clause", %{"clause-id" => ctx.other_clause.id})
    assert Repo.get(GroupRuleClause, ctx.other_clause.id)
  end

  test "add-qualification adds to this group's clause but not another team's", ctx do
    params = %{"qualification-id" => ctx.qualification.id}

    render_click(ctx.lv, "add-qualification", Map.put(params, "clause-id", ctx.clause.id))
    assert qualification_count(ctx.clause) == 1

    crash(ctx.lv, "add-qualification", Map.put(params, "clause-id", ctx.other_clause.id))
    assert qualification_count(ctx.other_clause) == 1
  end

  test "remove-qualification leaves another team's qualification", ctx do
    own = group_rule_clause_qualification_fixture(ctx.clause, ctx.qualification)

    render_click(ctx.lv, "remove-qualification", %{"qualification-id" => own.id})
    refute Repo.get(GroupRuleClauseQualification, own.id)

    other_id = ctx.other_clause_qualification.id
    crash(ctx.lv, "remove-qualification", %{"qualification-id" => other_id})
    assert Repo.get(GroupRuleClauseQualification, other_id)
  end

  test "a rule naming a qualification deleted in D4H shows a warning instead of changes", ctx do
    GroupRuleClauseQualification.insert!(%{
      group_rule_clause_id: ctx.clause.id,
      d4h_qualification_id: System.unique_integer([:positive])
    })

    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(lv, "#rule-broken")
  end

  # A miss raises and takes the LiveView down, as a 404 would on a page load.
  defp crash(lv, event, params) do
    Process.flag(:trap_exit, true)
    assert {{%Ecto.NoResultsError{}, _stack}, _call} = catch_exit(render_click(lv, event, params))
  end

  defp qualification_count(clause) do
    clause
    |> Ecto.assoc(:group_rule_clause_qualifications)
    |> Repo.aggregate(:count)
  end
end

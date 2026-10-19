defmodule Web.GroupLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.EndorsementQualification
  alias App.Model.GroupRule
  alias App.Model.GroupRuleReference

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
      other_team: other_team,
      other_endorsement: other_endorsement
    }
  end

  test "adds and removes rules, never with another team's endorsement", ctx do
    lv = ctx.lv
    lv |> element("#edit-rules") |> render_click()

    lv
    |> form("#add-rule-form", %{"kind" => "in", "target" => "endorsement:#{ctx.endorsement.id}"})
    |> render_submit()

    assert [%{kind: :in} = rule] = GroupRule.get_all(ctx.team.id)
    assert GroupRule.targets(rule) == [{:endorsement, ctx.endorsement.id}]

    lv |> element("#rule-#{rule.id} button", "Remove") |> render_click()
    assert GroupRule.get_all(ctx.team.id) == []

    crash(lv, "add-rule", %{"kind" => "in", "target" => "endorsement:#{ctx.other_endorsement.id}"})

    assert GroupRule.get_all(ctx.team.id) == []
  end

  test "a group built from groups reads as a sentence and follows their rules", ctx do
    gsar = group_fixture(ctx.team, %{title: "GSAR Qualified Callout"})
    group_rule_fixture(gsar, ctx.endorsement)
    mit = group_fixture(ctx.team, %{title: "MIT Callout"})
    loa = group_fixture(ctx.team, %{title: "LOA"})

    qualified = member_fixture(ctx.team, %{name: "Qualified"})
    qualification_award_fixture(ctx.qualification, qualified)
    by_hand = member_fixture(ctx.team, %{name: "By Hand"})
    group_member_fixture(gsar, by_hand)
    trainee = member_fixture(ctx.team, %{name: "Trainee"})
    group_member_fixture(mit, trainee)
    on_leave = member_fixture(ctx.team, %{name: "On Leave"})
    group_member_fixture(mit, on_leave)
    group_member_fixture(loa, on_leave)

    rule = group_rule_fixture(ctx.group, gsar)
    GroupRuleReference.add!(rule, mit)
    group_rule_fixture(ctx.group, loa, :not_in)

    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(
             lv,
             "#rule-sentence",
             "Members of GSAR Qualified Callout or MIT Callout who are not in LOA."
           )

    assert has_element?(lv, "#rule-group-#{gsar.id}", "Members must hold First Aid.")
    assert has_element?(lv, "#rule-group-#{loa.id}", "LOA is a list kept by hand in D4H.")
    assert has_element?(lv, "#would-add-#{qualified.id}")
    assert has_element?(lv, "#would-add-#{trainee.id}")
    refute has_element?(lv, "#would-add-#{by_hand.id}")
    refute has_element?(lv, "#would-add-#{on_leave.id}")
  end

  test "Standing is Active reads as a sentence and leaves out a member on leave (#366)", ctx do
    callout = group_fixture(ctx.team, %{title: "Qualified Callout"})
    trainees = group_fixture(ctx.team, %{title: "Trainee Callout"})
    today = Service.Period.today(DateTime.utc_now(), ctx.team.timezone)

    active = member_fixture(ctx.team, %{name: "Active Member"})
    group_member_fixture(callout, active)
    on_leave = member_fixture(ctx.team, %{name: "On Leave"})
    group_member_fixture(trainees, on_leave)
    group_member_fixture(ctx.group, on_leave)
    away_period_fixture(on_leave, Date.add(today, -1), Date.add(today, 30))

    rule = group_rule_fixture(ctx.group, callout)
    GroupRuleReference.add!(rule, trainees)

    {:ok, lv, _html} = live(ctx.conn, ctx.path)
    refute has_element?(lv, "#would-remove-#{on_leave.id}")

    lv |> element("#edit-rules") |> render_click()
    assert has_element?(lv, "#suggest-standing")
    lv |> element("#add-standing-active") |> render_click()

    assert [_in, %{kind: :standing} = standing] = GroupRule.get_all(ctx.team.id)
    assert GroupRule.targets(standing) == [{:standing, :active}]
    refute has_element?(lv, "#suggest-standing")

    lv |> element("#done-editing") |> render_click()

    assert has_element?(
             lv,
             "#rule-sentence",
             "Members of Qualified Callout or Trainee Callout who are active."
           )

    assert has_element?(lv, "#would-add-#{active.id}")
    assert has_element?(lv, "#would-remove-#{on_leave.id}", "Away until")
  end

  test "a standing joins the group's Standing rule, and only goes in one", ctx do
    group_rule_fixture(ctx.group, ctx.endorsement)
    lv = ctx.lv
    lv |> element("#edit-rules") |> render_click()

    lv
    |> form("#add-rule-form", %{"kind" => "standing", "target" => "standing:active"})
    |> render_submit()

    lv
    |> form("#add-rule-form", %{"kind" => "standing", "target" => "standing:away"})
    |> render_submit()

    assert [_in, %{kind: :standing} = standing] = GroupRule.get_all(ctx.team.id)
    assert GroupRule.targets(standing) == [{:standing, :active}, {:standing, :away}]

    html =
      lv
      |> form("#add-rule-form", %{"kind" => "in", "target" => "standing:not_a_person"})
      |> render_submit()

    assert html =~ "Select a group or endorsement for an In or Not in rule."
    assert length(GroupRule.get_all(ctx.team.id)) == 2
  end

  test "a Standing rule's page lists its standings and adds another", ctx do
    group_rule_fixture(ctx.group, ctx.endorsement)
    {:ok, rule} = GroupRule.add!(ctx.group, :standing, :active)

    {:ok, rule_lv, _html} =
      live(ctx.conn, ~p"/teams/#{ctx.team}/groups/#{ctx.group.id}/rules/#{rule.id}")

    assert has_element?(rule_lv, "#rule-meaning", "must have one of these standings today")
    assert has_element?(rule_lv, "#references", "Active")

    rule_lv |> form("#add-reference-form", %{"target" => "standing:away"}) |> render_submit()
    assert has_element?(rule_lv, "#references", "Away")

    refute has_element?(rule_lv, "#add-reference-form option", "First Aid")
    render_submit(rule_lv, "add", %{"target" => "endorsement:#{ctx.endorsement.id}"})

    assert ctx.group |> GroupRule.find!(rule.id) |> GroupRule.targets() == [
             {:standing, :active},
             {:standing, :away}
           ]
  end

  test "the menu leaves out a group that would make a loop, and refuses one sent anyway", ctx do
    gsar = group_fixture(ctx.team, %{title: "GSAR team"})
    group_rule_fixture(gsar, ctx.group)
    {:ok, lv, _html} = live(ctx.conn, ctx.path)
    lv |> element("#edit-rules") |> render_click()

    refute has_element?(lv, "#add-rule-form option[value='group:#{gsar.id}']")
    refute has_element?(lv, "#add-rule-form option[value='group:#{ctx.group.id}']")

    render_submit(lv, "add-rule", %{"kind" => "in", "target" => "group:#{gsar.id}"})
    assert ctx.team.id |> GroupRule.get_all() |> length() == 1
  end

  test "warns before the first rule changes what other groups count", ctx do
    callout = group_fixture(ctx.team, %{title: "Rope Rescue Callout"})
    group_rule_fixture(callout, ctx.group)
    {:ok, lv, _html} = live(ctx.conn, ctx.path)
    lv |> element("#edit-rules") |> render_click()

    assert lv |> element("#add-rule-form button") |> render() =~
             "Rope Rescue Callout uses this group&#39;s list. Once it has rules, Rope Rescue Callout uses its rules instead."

    lv
    |> form("#add-rule-form", %{"kind" => "in", "target" => "endorsement:#{ctx.endorsement.id}"})
    |> render_submit()

    [rule] =
      ctx.team.id
      |> GroupRule.get_all()
      |> Enum.filter(&(&1.d4h_group_id == ctx.group.d4h_group_id))

    assert lv |> element("#rule-#{rule.id} button") |> render() =~
             "Without them, Rope Rescue Callout uses its list in D4H instead."
  end

  test "the editor links each rule to its page, which adds and removes", ctx do
    rule = group_rule_fixture(ctx.group, ctx.endorsement)
    loa = group_fixture(ctx.team, %{title: "LOA"})
    {:ok, lv, _html} = live(ctx.conn, ctx.path)
    lv |> element("#edit-rules") |> render_click()

    path = ~p"/teams/#{ctx.team}/groups/#{ctx.group.id}/rules/#{rule.id}"
    assert has_element?(lv, ~s|#rule-#{rule.id} a[href="#{path}"]|, "First Aid")

    {:ok, rule_lv, _html} = live(ctx.conn, path)
    rule_lv |> form("#add-reference-form", %{"target" => "group:#{loa.id}"}) |> render_submit()
    assert has_element?(rule_lv, "#references", "LOA")

    [first | _] = GroupRule.find!(ctx.group, rule.id).references
    rule_lv |> element("#remove-reference-#{first.id}") |> render_click()
    assert [%{d4h_group_id: d4h_group_id}] = GroupRule.find!(ctx.group, rule.id).references
    assert d4h_group_id == loa.d4h_group_id

    [last] = GroupRule.find!(ctx.group, rule.id).references

    {:ok, _lv, html} =
      rule_lv
      |> element("#remove-reference-#{last.id}")
      |> render_click()
      |> follow_redirect(ctx.conn, ctx.path)

    assert html =~ "Rule removed."
    assert GroupRule.get_all(ctx.team.id) == []
  end

  test "another team's rule page is not found", ctx do
    other_group = group_fixture(ctx.other_team)
    rule = group_rule_fixture(other_group, ctx.other_endorsement)

    assert_raise Ecto.NoResultsError, fn ->
      live(ctx.conn, ~p"/teams/#{ctx.team}/groups/#{ctx.group.id}/rules/#{rule.id}")
    end
  end

  test "a rule naming a qualification deleted in D4H shows a warning instead of changes", ctx do
    group_rule_fixture(ctx.group, ctx.endorsement)

    EndorsementQualification.insert!(
      ctx.endorsement,
      System.unique_integer([:positive])
    )

    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(lv, "#rule-broken")
  end

  test "the rule reads by endorsement, and each removal says why", ctx do
    group_rule_fixture(ctx.group, ctx.endorsement)
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

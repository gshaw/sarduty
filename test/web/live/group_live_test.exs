defmodule Web.GroupLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.EndorsementQualification
  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
  alias App.Model.GroupRule
  alias App.Model.GroupRuleReference
  alias App.Operation.AddGroupRule
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
      user_email: user.email,
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
    assert has_element?(lv, "#rule-group-#{loa.id}", "LOA is a list kept by hand.")
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

  test "an Active members group needs only Standing is Active (#418)", ctx do
    today = Service.Period.today(DateTime.utc_now(), ctx.team.timezone)
    active = member_fixture(ctx.team, %{name: "Active Member"})
    on_leave = member_fixture(ctx.team, %{name: "On Leave"})
    away_period_fixture(on_leave, Date.add(today, -1), Date.add(today, 30))
    GroupRule.add!(ctx.group, :standing, :active)

    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(lv, "#rule-sentence", "Members who are active.")
    refute has_element?(lv, "#rule-broken")
    assert has_element?(lv, "#would-add-#{active.id}")
    refute has_element?(lv, "#would-add-#{on_leave.id}")
  end

  test "the menu follows the rule kind, and a standing joins the Standing rule", ctx do
    group_rule_fixture(ctx.group, ctx.endorsement)
    lv = ctx.lv
    lv |> element("#edit-rules") |> render_click()

    assert has_element?(lv, "#add-rule-form option", "First Aid")
    refute has_element?(lv, "#add-rule-form option[value='standing:active']")

    lv |> form("#add-rule-form", %{"kind" => "standing"}) |> render_change()
    assert has_element?(lv, "#add-rule-form option[value='standing:active']")
    refute has_element?(lv, "#add-rule-form option", "First Aid")

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
      |> element("#add-rule-form")
      |> render_submit(%{"kind" => "in", "target" => "standing:not_a_person"})

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

    assert lv |> element("#add-rule") |> render() =~
             "Rope Rescue Callout uses this group&#39;s list. Once it has rules, Rope Rescue Callout uses its rules instead."

    lv
    |> form("#add-rule-form", %{"kind" => "in", "target" => "endorsement:#{ctx.endorsement.id}"})
    |> render_submit()

    [rule] =
      ctx.team.id
      |> GroupRule.get_all()
      |> Enum.filter(&(&1.d4h_group_id == ctx.group.d4h_group_id))

    assert lv |> element("#rule-#{rule.id} button") |> render() =~
             "Without them, Rope Rescue Callout uses this group&#39;s list instead."
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
  describe "a group kept by hand (#546)" do
    setup ctx do
      team = ctx.team |> Ecto.Changeset.change(d4h_access_key: "key") |> Repo.update!()
      stub_d4h()
      %{team: team}
    end

    test "adds and removes members in D4H, and writes the copy without a sync", ctx do
      avery = member_fixture(ctx.team, %{name: "Avery Chen", d4h_member_id: 501})
      robin = member_fixture(ctx.team, %{name: "Robin Tse"})
      robin_in = group_member_fixture(ctx.group, robin)
      {:ok, lv, _html} = live(ctx.conn, ctx.path)

      refute has_element?(lv, "#members-by-rules")
      lv |> form("#add-member-form", %{member_id: avery.id}) |> render_submit()

      assert_received {:d4h, "POST", "/member-group-memberships", body}
      assert body == %{"groupId" => ctx.group.d4h_group_id, "memberId" => 501}
      added = Repo.get_by!(GroupMember, group_id: ctx.group.id, member_id: avery.id)
      assert added.d4h_group_membership_id == 400
      assert has_element?(lv, "#group-member-#{added.id}")
      refute has_element?(lv, "#flash-info")

      assert lv
             |> element("#remove-member-#{robin_in.id}")
             |> render() =~ ~s(data-confirm="Remove Robin Tse from #{ctx.group.title}?")

      lv |> element("#remove-member-#{robin_in.id}") |> render_click()

      path = "/member-group-memberships/#{robin_in.d4h_group_membership_id}"
      assert_received {:d4h, "DELETE", ^path, nil}
      refute Repo.get(GroupMember, robin_in.id)
      refute has_element?(lv, "#group-member-#{robin_in.id}")
      refute_received {:d4h, "GET", _path, _body}

      assert [removed, _added] = GroupMembershipChange.recent_for_group(ctx.group)
      assert %{action: :remove, reason: nil, error: nil} = removed
      assert has_element?(lv, "#recent-changes", "Added Avery Chen · by #{ctx.user_email}")
    end

    test "a group with rules has no add row or Remove, and refuses one sent anyway", ctx do
      member = member_fixture(ctx.team)
      group_member = group_member_fixture(ctx.group, member)
      group_rule_fixture(ctx.group, ctx.endorsement)
      {:ok, lv, _html} = live(ctx.conn, ctx.path)

      assert has_element?(lv, "#members-by-rules", "Its rules decide who is in it.")
      refute has_element?(lv, "#add-member-form")
      refute has_element?(lv, "#remove-member-#{group_member.id}")

      render_click(lv, "remove-member", %{"id" => to_string(group_member.id)})
      refute_received {:d4h, "DELETE", _path, _body}
      assert Repo.get(GroupMember, group_member.id)
    end

    test "names the groups whose rules use it", ctx do
      callout = group_fixture(ctx.team, %{title: "Callout"})
      group_rule_fixture(callout, ctx.group)
      {:ok, lv, _html} = live(ctx.conn, ctx.path)

      assert has_element?(lv, "#used-by", "The rules of Callout use this group.")

      assert has_element?(
               lv,
               ~s{#used-by a[href="/teams/#{ctx.team.subdomain}/groups/#{callout.id}"]}
             )
    end

    test "the organization's group can't be renamed or deleted, but takes members", ctx do
      organization_fixture([ctx.team], %{short_name: "BCSARA"})
      group = group_fixture(ctx.team, %{title: "Aircraft", organization_owned: true})
      member_fixture(ctx.team)
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/groups/#{group.id}")

      refute has_element?(lv, "#group-edit")
      assert has_element?(lv, "#group-organization", "Only BCSARA can rename or delete it.")
      assert has_element?(lv, "#add-member-form")

      assert_raise Web.Status.NotFound, fn ->
        live(ctx.conn, ~p"/teams/#{ctx.team}/groups/#{group.id}/edit")
      end
    end
  end

  # D4H's answer to each write, sent to the test. A read is sent too, so a test can say
  # nothing synced.
  defp stub_d4h do
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:d4h, conn.method, path, if(body != "", do: Jason.decode!(body))})

      case conn.method do
        "GET" ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0, "page" => 0})

        "POST" ->
          Req.Test.json(conn, %{"id" => 400, "member" => %{"id" => 1}, "group" => %{"id" => 1}})

        _method ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  defp crash(lv, event, params) do
    Process.flag(:trap_exit, true)
    assert {{%Ecto.NoResultsError{}, _stack}, _call} = catch_exit(render_click(lv, event, params))
  end

  test "the Retiring group cannot have rules (#514)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    leavers = group_fixture(team, %{title: "Leavers"})

    team
    |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id)
    |> App.Repo.update!()

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/groups/#{leavers.id}")

    assert has_element?(lv, "#retiring-group", "It cannot have group rules.")
    refute has_element?(lv, "#edit-rules")

    assert {:error, "Members of this group are retiring. It cannot have group rules."} =
             AddGroupRule.call(leavers, :standing, {:standing, :active})
  end
end

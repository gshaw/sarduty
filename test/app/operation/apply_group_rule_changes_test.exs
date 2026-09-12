defmodule App.Operation.ApplyGroupRuleChangesTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
  alias App.Model.Member
  alias App.Operation.ApplyGroupRuleChanges

  setup do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    group = group_fixture(team)
    qualification = qualification_fixture(team)
    clause = group_rule_clause_fixture(group)
    group_rule_clause_qualification_fixture(clause, qualification)

    unqualified = member_fixture(team, %{name: "Jordan Lee"})
    membership = group_member_fixture(group, unqualified)
    qualified = member_fixture(team, %{name: "Taylor Brooks"})
    qualification_award_fixture(qualification, qualified)

    %{
      user: user,
      team: team,
      group: group,
      unqualified: unqualified,
      membership: membership,
      qualified: qualified
    }
  end

  test "sends the ticked changes to D4H, updates the local copy, and logs each", ctx do
    group_id = ctx.group.d4h_group_id
    member_id = ctx.qualified.d4h_member_id

    delete_path =
      "/v3/team/#{ctx.team.d4h_team_id}/member-group-memberships/#{ctx.membership.d4h_group_membership_id}"

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v3/team/" <> _} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert Jason.decode!(body) == %{"groupId" => group_id, "memberId" => member_id}
          Req.Test.json(conn, membership_json(4242, group_id, member_id))

        {"DELETE", ^delete_path} ->
          Req.Test.json(conn, %{"deleted" => true})
      end
    end)

    selected = [ctx.qualified.id, ctx.unqualified.id]

    assert {:ok, %{applied: 2, failed: 0}} =
             ApplyGroupRuleChanges.call(ctx.team, ctx.group, ctx.user, selected)

    refute Repo.get(GroupMember, ctx.membership.id)

    assert GroupMember.get_by(group_id: ctx.group.id, member_id: ctx.qualified.id).d4h_group_membership_id ==
             4242

    assert [%{action: :remove, error: nil}, %{action: :add, error: nil, user_id: user_id}] =
             GroupMembershipChange |> order_by([c], c.id) |> Repo.all()

    assert user_id == ctx.user.id
  end

  test "a member not ticked, or one the plan doesn't list, is left alone", ctx do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      Req.Test.json(
        conn,
        membership_json(4242, ctx.group.d4h_group_id, ctx.qualified.d4h_member_id)
      )
    end)

    other_team_member = member_fixture(team_fixture())
    selected = [ctx.qualified.id, other_team_member.id]

    assert {:ok, %{applied: 1, failed: 0}} =
             ApplyGroupRuleChanges.call(ctx.team, ctx.group, ctx.user, selected)

    assert Repo.get(GroupMember, ctx.membership.id)
    assert Repo.aggregate(GroupMembershipChange, :count) == 1
  end

  test "a change D4H rejects is logged with the error and the rest still run", ctx do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      case conn.method do
        "POST" -> conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"title" => "Forbidden"})
        "DELETE" -> Req.Test.json(conn, %{"deleted" => true})
      end
    end)

    selected = [ctx.qualified.id, ctx.unqualified.id]

    assert {:ok, %{applied: 1, failed: 1}} =
             ApplyGroupRuleChanges.call(ctx.team, ctx.group, ctx.user, selected)

    refute GroupMember.get_by(group_id: ctx.group.id, member_id: ctx.qualified.id)

    assert %{error: "D4H API error (403): Forbidden"} =
             Repo.get_by(GroupMembershipChange, action: :add)
  end

  test "without a team key nothing is sent", ctx do
    team = %{ctx.team | d4h_access_key: nil}

    assert {:error, :no_team_key} =
             ApplyGroupRuleChanges.call(team, ctx.group, ctx.user, [ctx.qualified.id])

    assert Repo.aggregate(GroupMembershipChange, :count) == 0
  end

  test "select_changes keeps only ticked members, removals first" do
    alex = %Member{id: 1, name: "Alex"}
    taylor = %Member{id: 2, name: "Taylor"}
    sam = %Member{id: 3, name: "Sam"}

    preview = %{
      to_add: [%{member: taylor, reason: "Meets all rules"}],
      to_remove: [%{member: alex, reason: "No Rope on record"}, %{member: sam, reason: "Left"}]
    }

    assert [%{action: :remove, member: ^alex}, %{action: :add, member: ^taylor}] =
             ApplyGroupRuleChanges.select_changes(preview, [2, 1, 99])
  end

  # The shape D4H's API spec gives for a created membership.
  defp membership_json(id, group_id, member_id) do
    %{
      "id" => id,
      "resourceType" => "MemberGroupMembership",
      "group" => %{"resourceType" => "MemberGroup", "id" => group_id},
      "member" => %{"resourceType" => "Member", "id" => member_id}
    }
  end
end

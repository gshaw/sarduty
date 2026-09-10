defmodule Web.GroupReviewLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.GroupMember
  alias App.Model.GroupMembershipChange
  alias App.Model.Team
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    group = group_fixture(team)
    qualification = qualification_fixture(team)
    group |> group_rule_clause_fixture() |> group_rule_clause_qualification_fixture(qualification)

    unqualified = member_fixture(team, %{name: "Jordan Lee"})
    group_member_fixture(group, unqualified)
    qualified = member_fixture(team, %{name: "Taylor Brooks"})
    qualification_award_fixture(qualification, qualified)

    %{
      conn: log_in_user(conn, user),
      team: team,
      group: group,
      unqualified: unqualified,
      qualified: qualified,
      path: ~p"/#{team.subdomain}/groups/#{group.id}/review"
    }
  end

  test "lists each change with its reason, all ticked", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(lv, "#review-remove-#{ctx.unqualified.id}", "on record")
    assert has_element?(lv, "#select-#{ctx.unqualified.id}[checked]")
    assert has_element?(lv, "#review-add-#{ctx.qualified.id}", "Meets all rules")
    assert has_element?(lv, "#apply", "Apply 2 changes in D4H")
  end

  test "applying sends only the ticked changes and returns to the group", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path)
    Req.Test.allow(App.Adapter.D4H, self(), lv.pid)

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      Req.Test.json(conn, %{
        "id" => 4242,
        "group" => %{"id" => ctx.group.d4h_group_id},
        "member" => %{"resourceType" => "Member", "id" => ctx.qualified.d4h_member_id}
      })
    end)

    lv |> form("#review-form", %{"member_ids" => ["#{ctx.qualified.id}"]}) |> render_change()
    assert has_element?(lv, "#apply", "Apply 1 change in D4H")

    lv
    |> form("#review-form", %{"member_ids" => ["#{ctx.qualified.id}"]})
    |> render_submit()

    assert_redirect(lv, ~p"/#{ctx.team.subdomain}/groups/#{ctx.group.id}")
    assert GroupMember.get_by(group_id: ctx.group.id, member_id: ctx.qualified.id)
    assert GroupMember.get_by(group_id: ctx.group.id, member_id: ctx.unqualified.id)
    assert [%{action: :add}] = Repo.all(GroupMembershipChange)
  end

  test "without a team key the page says so and can't apply", ctx do
    {:ok, _} = ctx.team.id |> Team.get!() |> Team.update(%{d4h_access_key: nil})

    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(lv, "#no-team-key")
    assert has_element?(lv, "#apply[disabled]")
  end
end

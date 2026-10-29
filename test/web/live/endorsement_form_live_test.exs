defmodule Web.EndorsementFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.Model.GroupRule
  alias App.Model.GroupRuleReference
  alias App.Repo

  @moduletag :capture_log

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), team: team}
  end

  test "adds one from a group's rule editor, and it becomes an In rule", %{conn: conn, team: team} do
    group = group_fixture(team)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements/new?group_id=#{group.id}")

    {:ok, _lv, _html} =
      lv
      |> form("#endorsement-form", endorsement: %{name: " First Aid "})
      |> render_submit()
      |> follow_redirect(conn)

    endorsement = Repo.get_by!(Endorsement, team_id: team.id, name: "First Aid")
    assert [%{kind: :in} = rule] = GroupRule.get_all(team.id)
    assert {:endorsement, endorsement.id} in GroupRule.targets(rule)
    assert rule.d4h_group_id == group.d4h_group_id
  end

  test "a name already in use is an error", %{conn: conn, team: team} do
    endorsement_fixture(team, %{name: "GSAR"})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements/new")
    assert has_element?(lv, ~s|#endorsement-cancel[href="#{~p"/teams/#{team}/endorsements"}"]|)

    html = lv |> form("#endorsement-form", endorsement: %{name: "GSAR"}) |> render_submit()

    assert html =~ "Use a name no other endorsement has."
  end

  test "adds and removes qualifications, only the team's own", %{conn: conn, team: team} do
    endorsement = endorsement_fixture(team)
    qualification = qualification_fixture(team)
    theirs = qualification_fixture(team_fixture())
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements/#{endorsement.id}")
    refute has_element?(lv, "#endorsement-cancel")

    render_submit(lv, "add-qualification", %{"qualification-id" => qualification.id})

    saved = Endorsement.get!(team.id, endorsement.id)
    assert Endorsement.qualification_ids(saved) == [qualification.d4h_qualification_id]

    [row] = Repo.all(EndorsementQualification)
    lv |> element("#remove-qualification-#{row.id}") |> render_click()
    assert Repo.all(EndorsementQualification) == []

    Process.flag(:trap_exit, true)

    assert {{%Ecto.NoResultsError{}, _}, _} =
             catch_exit(
               render_submit(lv, "add-qualification", %{"qualification-id" => theirs.id})
             )
  end

  test "a qualification is picked from a combobox, and the form sends it as a select", %{
    conn: conn,
    team: team
  } do
    endorsement = endorsement_fixture(team)
    qualification = qualification_fixture(team)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements/#{endorsement.id}")

    assert has_element?(lv, "#qualification-id[role=combobox]")
    assert has_element?(lv, "#qualification-id-select option[value='#{qualification.id}']")

    lv
    |> form("#add-qualification-form", %{"qualification-id" => qualification.id})
    |> render_submit()

    saved = Endorsement.get!(team.id, endorsement.id)
    assert Endorsement.qualification_ids(saved) == [qualification.d4h_qualification_id]
    refute has_element?(lv, "#qualification-id-select option[value='#{qualification.id}']")
  end

  test "includes another endorsement, never one that makes a loop", %{conn: conn, team: team} do
    seven = endorsement_fixture(team, %{name: "First Aid 7"})
    seventy = endorsement_fixture(team, %{name: "First Aid 70"})
    ofa3 = qualification_fixture(team)
    endorsement_qualification_fixture(seventy, ofa3)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements/#{seven.id}")

    render_submit(lv, "add-include", %{"endorsement-id" => seventy.id})

    assert has_element?(lv, "#include-#{seventy.id}", "First Aid 70")
    refute has_element?(lv, "#no-qualifications")

    saved = Endorsement.get!(team.id, seven.id)
    assert Endorsement.qualification_ids(saved) == [ofa3.d4h_qualification_id]

    {:ok, lv70, _html} = live(conn, ~p"/teams/#{team}/endorsements/#{seventy.id}")
    assert has_element?(lv70, "#endorsement-counts-toward a", "First Aid 7")
    refute has_element?(lv70, "#add-include-form option[value='#{seven.id}']")

    render_submit(lv70, "add-include", %{"endorsement-id" => seven.id})
    assert Endorsement.get!(team.id, seventy.id).included_ids == []

    lv |> element("#remove-include-#{seventy.id}") |> render_click()
    assert Endorsement.get!(team.id, seven.id).included_ids == []
  end

  test "deleting takes it out of every rule, and a rule it leaves empty goes", %{
    conn: conn,
    team: team
  } do
    endorsement = endorsement_fixture(team)
    group = group_fixture(team)
    other = group_fixture(team, %{title: "LOA"})
    group_rule_fixture(group, endorsement)
    shared = group_rule_fixture(group, other, :not_in)
    GroupRuleReference.add!(shared, endorsement)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements/#{endorsement.id}")

    assert has_element?(lv, "#endorsement-groups a", group.title)

    assert lv |> element("#endorsement-delete") |> render() =~
             "It comes off ID cards and the rules of #{group.title}."

    {:ok, _lv, _html} =
      lv |> element("#endorsement-delete") |> render_click() |> follow_redirect(conn)

    assert [%{id: id} = rule] = GroupRule.get_all(team.id)
    assert id == shared.id
    assert GroupRule.targets(rule) == [{:group, other.d4h_group_id}]
    refute Repo.get(Endorsement, endorsement.id)
  end
end

defmodule Web.EndorsementFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.Repo

  @moduletag :capture_log

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), team: team}
  end

  test "adds one from a group's rule editor, and it joins the rule", %{conn: conn, team: team} do
    group = group_fixture(team)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements/new?group_id=#{group.id}")

    {:ok, _lv, _html} =
      lv
      |> form("#endorsement-form", endorsement: %{name: " First Aid "})
      |> render_submit()
      |> follow_redirect(conn)

    assert [%{name: "First Aid"}] = Endorsement.get_all_for_group(group)
  end

  test "a name already in use is an error", %{conn: conn, team: team} do
    endorsement_fixture(team, %{name: "GSAR"})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements/new")

    html = lv |> form("#endorsement-form", endorsement: %{name: "GSAR"}) |> render_submit()

    assert html =~ "is already an endorsement"
  end

  test "adds and removes qualifications, only the team's own", %{conn: conn, team: team} do
    endorsement = endorsement_fixture(team)
    qualification = qualification_fixture(team)
    theirs = qualification_fixture(team_fixture())
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements/#{endorsement.id}")

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

  test "deleting takes it out of every group rule", %{conn: conn, team: team} do
    endorsement = endorsement_fixture(team)
    group = group_fixture(team)
    group_endorsement_fixture(group, endorsement)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements/#{endorsement.id}")

    assert has_element?(lv, "#endorsement-groups a", group.title)

    {:ok, _lv, _html} =
      lv |> element("#endorsement-delete") |> render_click() |> follow_redirect(conn)

    assert Endorsement.get_all_for_group(group) == []
    refute Repo.get(Endorsement, endorsement.id)
  end
end

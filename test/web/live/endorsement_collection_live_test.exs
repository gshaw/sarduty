defmodule Web.EndorsementCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.EndorsementQualification
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    team = team |> Ecto.Changeset.change(id_cards_enabled: true) |> Repo.update!()
    %{conn: log_in_user(conn, user), team: team}
  end

  test "says so when the team has none", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements")
    assert has_element?(lv, "#no-endorsements")
  end

  test "lists what earns each one, who holds it, and the group rules that use it",
       %{conn: conn, team: team} do
    group = group_fixture(team, %{title: "GSAR Callout"})
    basic = qualification_fixture(team, %{title: "OFA 1"})
    advanced = qualification_fixture(team, %{title: "OFA 3"})
    qualification_award_fixture(basic, member_fixture(team))
    qualification_award_fixture(advanced, member_fixture(team))
    first_aid = endorsement_fixture(team, %{name: "First Aid"})
    endorsement_qualification_fixture(first_aid, basic)
    endorsement_qualification_fixture(first_aid, advanced)
    group_rule_fixture(group, first_aid)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements")

    assert has_element?(lv, "#endorsement-#{first_aid.id} td", "OFA 1, OFA 3")
    assert has_element?(lv, "#endorsement-#{first_aid.id} td", ~r/^\s*2\s*$/)

    assert has_element?(
             lv,
             ~s|#endorsement-#{first_aid.id} a[href="/teams/#{team.subdomain}/groups/#{group.id}"]|
           )

    refute has_element?(lv, "#endorsement-problems")
  end

  test "flags two endorsements with the same qualifications, and one with no qualifications",
       %{conn: conn, team: team} do
    pslv = qualification_fixture(team)
    qualification_award_fixture(pslv, member_fixture(team))
    short = endorsement_fixture(team, %{name: "PSLV"})
    long = endorsement_fixture(team, %{name: "PSLV Registration"})
    endorsement_qualification_fixture(short, pslv)
    endorsement_qualification_fixture(long, pslv)
    placeholder = endorsement_fixture(team, %{name: "Placeholder"})
    rope = endorsement_fixture(team, %{name: "Rope"})
    endorsement_qualification_fixture(rope, qualification_fixture(team))

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements")

    assert has_element?(lv, "#endorsement-#{short.id}-same-as-#{long.id}", "PSLV Registration")
    assert has_element?(lv, "#endorsement-#{long.id}-same-as-#{short.id}")
    assert has_element?(lv, "#endorsement-#{placeholder.id}-empty")
    assert has_element?(lv, "#endorsement-problems a[href='#endorsement-#{placeholder.id}']")
    refute has_element?(lv, "#endorsement-problems a[href='#endorsement-#{rope.id}']")
  end

  test "flags a qualification no longer in D4H", %{conn: conn, team: team} do
    rope = endorsement_fixture(team, %{name: "Rope"})
    EndorsementQualification.insert!(rope, System.unique_integer([:positive]))

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements")

    assert has_element?(lv, "#endorsement-#{rope.id}-missing a")
  end

  test "picks what ID cards list, and says when a stricter one stands in",
       %{conn: conn, team: team} do
    seven = qualification_fixture(team)
    seventy = qualification_fixture(team)
    basic = endorsement_fixture(team, %{name: "First Aid (7 hours or higher)", on_card: true})
    advanced = endorsement_fixture(team, %{name: "First Aid (70 hours or higher)"})
    endorsement_qualification_fixture(basic, seven)
    endorsement_qualification_fixture(basic, seventy)
    endorsement_qualification_fixture(advanced, seventy)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements")
    refute has_element?(lv, "#endorsement-#{basic.id}-hidden")

    lv
    |> form("#endorsements-form")
    |> render_submit(%{"ids" => ["", to_string(basic.id), to_string(advanced.id)]})

    assert Repo.reload!(advanced).on_card
    assert has_element?(lv, "#endorsement-#{basic.id}-hidden", "First Aid (70 hours or higher)")

    lv |> form("#endorsements-form") |> render_submit(%{"ids" => [""]})
    refute Repo.reload!(basic).on_card
  end

  test "never changes another team's endorsements", %{conn: conn, team: team} do
    endorsement_fixture(team)
    theirs = endorsement_fixture(team_fixture(), %{on_card: true})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements")
    lv |> form("#endorsements-form") |> render_submit(%{"ids" => ["", to_string(theirs.id)]})

    assert Repo.reload!(theirs).on_card
  end

  test "without ID cards there is nothing to tick", %{conn: conn, team: team} do
    team = team |> Ecto.Changeset.change(id_cards_enabled: false) |> Repo.update!()
    endorsement_fixture(team)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/endorsements")

    refute has_element?(lv, "#endorsements-form input[type=checkbox]")
  end
end

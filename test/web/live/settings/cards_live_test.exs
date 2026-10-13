defmodule Web.Settings.CardsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.PassRegistration
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), team: team}
  end

  test "says so when the team has no named clauses", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/cards")
    assert has_element?(lv, "#no-names")
  end

  test "ticks a name on for every clause with it, and off again", %{conn: conn, team: team} do
    group = group_fixture(team)
    other_group = group_fixture(team)
    first_aid = group_rule_clause_fixture(group, %{name: "First Aid"})
    first_aid_too = group_rule_clause_fixture(other_group, %{name: "First Aid"})
    rope = group_rule_clause_fixture(group, %{name: "Rope"})
    group_rule_clause_fixture(group)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/cards")
    lv |> form("#cards-form") |> render_submit(%{"names" => ["", "First Aid"]})

    assert Repo.reload!(first_aid).on_card
    assert Repo.reload!(first_aid_too).on_card
    refute Repo.reload!(rope).on_card

    lv |> form("#cards-form") |> render_submit(%{"names" => [""]})
    refute Repo.reload!(first_aid).on_card
  end

  test "links to the groups to fix a name no member holds", %{conn: conn, team: team} do
    gsar = group_fixture(team, %{title: "GSAR Callout"})
    members = group_fixture(team, %{title: "Members"})
    held = qualification_fixture(team)
    qualification_award_fixture(held, member_fixture(team))

    for group <- [gsar, members] do
      group_rule_clause_fixture(group, %{name: "Placeholder"})
    end

    group_rule_clause_qualification_fixture(
      group_rule_clause_fixture(members, %{name: "Rope"}),
      held
    )

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/cards")

    assert has_element?(lv, "#card-name-0-no-members")

    assert has_element?(
             lv,
             ~s|#card-name-0-fix a[href="/teams/#{team.subdomain}/groups/#{gsar.id}"]|
           )

    assert has_element?(
             lv,
             ~s|#card-name-0-fix a[href="/teams/#{team.subdomain}/groups/#{members.id}"]|
           )

    refute has_element?(lv, "#card-name-1-fix")
  end

  test "shows every qualification under a name and how many members hold one",
       %{conn: conn, team: team} do
    first = group_fixture(team)
    second = group_fixture(team)
    basic = qualification_fixture(team, %{title: "OFA 1"})
    advanced = qualification_fixture(team, %{title: "OFA 3"})
    qualification_award_fixture(basic, member_fixture(team))
    qualification_award_fixture(advanced, member_fixture(team))
    qualification_award_fixture(advanced, member_fixture(team, %{d4h_status: "RETIRED"}))

    for {group, qualification} <- [{first, basic}, {second, advanced}] do
      clause = group_rule_clause_fixture(group, %{name: "First Aid"})
      group_rule_clause_qualification_fixture(clause, qualification)
    end

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/cards")

    assert has_element?(lv, "#card-name-0 td", "OFA 1, OFA 3")
    assert has_element?(lv, "#card-name-0 td", ~r/^\s*2\s*$/)
  end

  test "flags a qualification no longer in D4H", %{conn: conn, team: team} do
    clause = group_rule_clause_fixture(group_fixture(team), %{name: "Rope"})

    group_rule_clause_qualification_fixture(clause, %App.Model.Qualification{
      d4h_qualification_id: 1
    })

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/cards")

    assert has_element?(lv, "#card-name-0-missing")
    assert has_element?(lv, "#card-name-0-fix a")
  end

  test "never changes another team's clauses", %{conn: conn, team: team} do
    group_rule_clause_fixture(group_fixture(team), %{name: "First Aid"})

    theirs =
      group_rule_clause_fixture(group_fixture(team_fixture()), %{name: "First Aid", on_card: true})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/cards")
    lv |> form("#cards-form") |> render_submit(%{"names" => [""]})

    assert Repo.reload!(theirs).on_card
  end

  test "saving pushes the change to passes on phones", %{conn: conn, team: team} do
    App.ApplePassCredentials.configure()
    test_pid = self()

    Req.Test.stub(App.Adapter.APNs, fn conn ->
      send(test_pid, {:pushed, conn.request_path})
      Plug.Conn.send_resp(conn, 200, "")
    end)

    member = member_fixture(team)
    card = member_card_fixture(member, %{authentication_token: "token-0123456789abcdef"})
    PassRegistration.register!(card, "device-1", "push-token-1")
    group_rule_clause_fixture(group_fixture(team), %{name: "First Aid"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/cards")
    lv |> form("#cards-form") |> render_submit(%{"names" => ["", "First Aid"]})

    assert_received {:pushed, "/3/device/push-token-1"}
  end
end

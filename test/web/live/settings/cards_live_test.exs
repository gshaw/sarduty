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

  test "lists the groups that use each name, linked to the group", %{conn: conn, team: team} do
    gsar = group_fixture(team, %{title: "GSAR Callout"})
    members = group_fixture(team, %{title: "Members"})
    group_rule_clause_fixture(gsar, %{name: "GSAR"})
    group_rule_clause_fixture(members, %{name: "GSAR"})
    group_rule_clause_fixture(members, %{name: "Rope"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/cards")

    assert has_element?(lv, ~s|#card-name-0 a[href="/teams/#{team.subdomain}/groups/#{gsar.id}"]|)

    assert has_element?(
             lv,
             ~s|#card-name-0 a[href="/teams/#{team.subdomain}/groups/#{members.id}"]|
           )

    refute has_element?(lv, ~s|#card-name-1 a[href="/teams/#{team.subdomain}/groups/#{gsar.id}"]|)
  end

  test "warns when groups list different qualifications under one name",
       %{conn: conn, team: team} do
    first = group_fixture(team)
    second = group_fixture(team)
    same = group_fixture(team)
    [basic, advanced, rope] = for _ <- 1..3, do: qualification_fixture(team)

    for {group, name, qualification} <- [
          {first, "First Aid", basic},
          {second, "First Aid", advanced},
          {first, "Rope", rope},
          {same, "Rope", rope}
        ] do
      clause = group_rule_clause_fixture(group, %{name: name})
      group_rule_clause_qualification_fixture(clause, qualification)
    end

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/cards")

    assert has_element?(lv, "#card-name-0-mixed")
    refute has_element?(lv, "#card-name-1-mixed")
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

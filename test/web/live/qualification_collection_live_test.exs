defmodule Web.QualificationCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders qualifications page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "First Aid"})
    member = member_fixture(team)
    qualification_award_fixture(qualification, member)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications")

    assert html =~ "Qualifications"
    assert html =~ "First Aid"
  end

  test "the organization's qualifications name it (#652)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    organization_fixture([team], %{short_name: "BCSARA"})
    owned = qualification_fixture(team, %{title: "GSAR Team Member", organization_owned: true})
    own = qualification_fixture(team, %{title: "Driver Truck"})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/qualifications")

    assert has_element?(lv, "#qualification-#{owned.id}", "GSAR Team Member · BCSARA")
    refute has_element?(lv, "#qualification-#{own.id}", "BCSARA")
  end

  test "renders empty qualifications page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications")

    assert html =~ "Qualifications"
    assert html =~ "No qualifications yet"
    refute html =~ "0 qualifications"
  end

  test "a qualification's row counts its members as its own page does", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "First Aid"})
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    ago = &DateTime.add(now, -&1, :day)

    renewed = member_fixture(team, %{name: "Renewed Member"})

    qualification_award_fixture(qualification, renewed, %{starts_at: ago.(800), ends_at: ago.(30)})

    qualification_award_fixture(qualification, renewed, %{starts_at: ago.(30), ends_at: nil})

    lapsed = member_fixture(team, %{name: "Lapsed Member"})

    qualification_award_fixture(qualification, lapsed, %{starts_at: ago.(900), ends_at: ago.(500)})

    qualification_award_fixture(qualification, lapsed, %{starts_at: ago.(500), ends_at: ago.(10)})

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/qualifications")
    row = "#qualification-#{qualification.id}"

    assert has_element?(lv, "#{row} td:nth-child(2)", "1")
    assert has_element?(lv, "#{row} td:nth-child(3)", "1")
    assert has_element?(lv, "#{row} td:nth-child(4)", "2")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/qualifications/#{qualification.id}")
    assert has_element?(lv, "#awards-all-link", "2")
    assert has_element?(lv, "#awards-active-link", "1")
    assert has_element?(lv, "#awards-expired-link", "1")
  end

  test "links to qualification detail page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification_fixture(team, %{title: "Swift Water Rescue"})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications")

    assert has_element?(lv, "a", "Swift Water Rescue")
  end

  test "the expiring view lists each current member's latest award ending in 60 days",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "First Aid"})
    soon = DateTime.utc_now() |> DateTime.add(10, :day) |> DateTime.truncate(:second)
    later = DateTime.add(soon, 400, :day)

    expiring = member_fixture(team, %{name: "Expiring Member"})
    qualification_award_fixture(qualification, expiring, %{ends_at: soon})

    renewed = member_fixture(team, %{name: "Renewed Member"})
    qualification_award_fixture(qualification, renewed, %{ends_at: soon})
    qualification_award_fixture(qualification, renewed, %{ends_at: later})

    retired = member_fixture(team, %{name: "Retired Member", left_at: ~U[2025-01-01 00:00:00Z]})
    qualification_award_fixture(qualification, retired, %{ends_at: soon})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications?view=expiring")

    assert has_element?(lv, "#expiring-#{expiring.id}-#{qualification.id}", "First Aid")
    refute has_element?(lv, "#expiring_qualifications", "Renewed Member")
    refute has_element?(lv, "#expiring_qualifications", "Retired Member")
  end

  test "the expiring view's Group filter keeps the group's members only (#367)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "First Aid"})
    soon = DateTime.utc_now() |> DateTime.add(10, :day) |> DateTime.truncate(:second)
    callout = group_fixture(team, %{title: "Callout"})

    in_callout = member_fixture(team, %{name: "In Callout"})
    qualification_award_fixture(qualification, in_callout, %{ends_at: soon})
    group_member_fixture(callout, in_callout)

    not_in_callout = member_fixture(team, %{name: "Not In Callout"})
    qualification_award_fixture(qualification, not_in_callout, %{ends_at: soon})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/qualifications?view=expiring")

    lv |> form("#qualification_filter_form", form: %{group: callout.id}) |> render_change()

    assert_patched(lv, ~p"/teams/#{team}/qualifications?view=expiring&group=#{callout.id}")
    assert has_element?(lv, "#expiring-#{in_callout.id}-#{qualification.id}")
    refute has_element?(lv, "#expiring-#{not_in_callout.id}-#{qualification.id}")
  end

  test "the expiring view's Group filter finds no one in another team's group",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team)
    soon = DateTime.utc_now() |> DateTime.add(10, :day) |> DateTime.truncate(:second)
    member = member_fixture(team)
    qualification_award_fixture(qualification, member, %{ends_at: soon})

    other_team = team_fixture()
    other_group = group_fixture(other_team)
    group_member_fixture(other_group, member)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications?view=expiring&group=#{other_group.id}")

    refute has_element?(lv, "#expiring-#{member.id}-#{qualification.id}")
    assert has_element?(lv, "#no-matching-qualifications")
  end

  test "the Within filter looks further ahead and names the view (#367)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team)
    in_80_days = DateTime.utc_now() |> DateTime.add(80, :day) |> DateTime.truncate(:second)
    member = member_fixture(team)
    qualification_award_fixture(qualification, member, %{ends_at: in_80_days})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/qualifications?view=expiring")

    assert has_element?(lv, "#qualifications-expiring-link", "Awards expiring in 60 days")
    refute has_element?(lv, "#expiring-#{member.id}-#{qualification.id}")

    lv |> form("#qualification_filter_form", form: %{within: "90"}) |> render_change()

    assert_patched(lv, ~p"/teams/#{team}/qualifications?view=expiring&within=90")
    assert has_element?(lv, "#qualifications-expiring-link", "Awards expiring in 90 days")
    assert has_element?(lv, "#expiring-#{member.id}-#{qualification.id}")
  end

  test "a time frame the Within filter does not offer is not found", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    assert_raise Web.Status.NotFound, fn ->
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/qualifications?view=expiring&within=7")
    end
  end
end

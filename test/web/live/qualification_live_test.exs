defmodule Web.QualificationLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders qualification page with active and expired awards", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "Rope Rescue"})

    active_member = member_fixture(team, %{name: "Alice Active"})

    qualification_award_fixture(qualification, active_member, %{
      starts_at: DateTime.add(DateTime.utc_now(), -365, :day),
      ends_at: DateTime.add(DateTime.utc_now(), 365, :day)
    })

    expired_member = member_fixture(team, %{name: "Bob Expired"})

    qualification_award_fixture(qualification, expired_member, %{
      starts_at: DateTime.add(DateTime.utc_now(), -730, :day),
      ends_at: DateTime.add(DateTime.utc_now(), -365, :day)
    })

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications/#{qualification.id}")

    assert html =~ "Rope Rescue"
    assert has_element?(lv, "#active_awards", "Alice Active")
    refute has_element?(lv, "#active_awards", "Bob Expired")
    assert has_element?(lv, "#awards-expired-link", "1")

    lv |> element("#awards-expired-link") |> render_click()
    assert has_element?(lv, "#expired_awards", "Bob Expired")
    refute has_element?(lv, "#expired_awards", "Alice Active")

    assert has_element?(lv, "#awards-all-link", "2")
    lv |> element("#awards-all-link") |> render_click()
    assert has_element?(lv, "#all_awards tr:not(.is-muted)", "Alice Active")
    assert has_element?(lv, "#all_awards tr.is-muted", "Bob Expired")
  end

  test "Open in D4H links to the qualification's course page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "Drivers Abstract"})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications/#{qualification.id}")

    href = "/team/courses/view/#{qualification.d4h_qualification_id}"
    assert has_element?(lv, ~s|#qualification-d4h[href$="#{href}"]|)
  end

  test "search finds members in the view (#350)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team)

    for name <- ["Fiona MacLeod", "Blake Okafor"] do
      qualification_award_fixture(qualification, member_fixture(team, %{name: name}))
    end

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/qualifications/#{qualification.id}")

    lv |> form("#award_filter_form", form: %{q: "FIONA"}) |> render_change()

    assert has_element?(lv, "#active_awards", "Fiona MacLeod")
    refute has_element?(lv, "#active_awards", "Blake Okafor")
    assert has_element?(lv, "#award_filter_form-summary", "1 member")
  end

  test "renders qualification page with no awards", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "Empty Qual"})

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications/#{qualification.id}")

    assert html =~ "Empty Qual"
    assert html =~ "No members hold it now."

    lv |> element("#awards-expired-link") |> render_click()
    assert render(lv) =~ "No members have let it expire."
  end

  test "the organization's qualification says who it belongs to (#652)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    organization_fixture([team], %{short_name: "BCSARA"})

    qualification =
      qualification_fixture(team, %{title: "GSAR Team Member", organization_owned: true})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/qualifications/#{qualification.id}")

    assert has_element?(lv, "#qualification-organization", "Only BCSARA can rename or delete it.")
  end

  test "the Group filter keeps the group's members only (#367)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team)
    callout = group_fixture(team, %{title: "Callout"})
    in_callout = member_fixture(team, %{name: "Fiona MacLeod"})
    group_member_fixture(callout, in_callout)
    qualification_award_fixture(qualification, in_callout)
    qualification_award_fixture(qualification, member_fixture(team, %{name: "Blake Okafor"}))

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/qualifications/#{qualification.id}")

    lv |> form("#award_filter_form", form: %{group: callout.id}) |> render_change()

    assert_patched(lv, ~p"/teams/#{team}/qualifications/#{qualification.id}?group=#{callout.id}")
    assert has_element?(lv, "#active_awards", "Fiona MacLeod")
    refute has_element?(lv, "#active_awards", "Blake Okafor")
  end
end

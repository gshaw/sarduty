defmodule Web.HomePageLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import Phoenix.LiveViewTest

  test "a visitor sees what SAR Duty is for, and sign up and log in", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, "#home-title")
    assert has_element?(lv, ~s(#start-top a[href="/signup"]))
    assert has_element?(lv, ~s(#start-top a[href="/login"]))
    assert has_element?(lv, ~s(#start-end a[href="/signup"]))
  end

  test "the page links to where a tax credit letter is verified", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(a[href="#{Web.VerifyHost.url()}/letters"]))
  end

  test "a logged-in user with no team is told where access comes from", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/")

    assert has_element?(lv, "#start-top", "You are not on a team yet")
    assert has_element?(lv, ~s(#start-top a[href="/signup"]))
    refute has_element?(lv, ~s(#start-top a[href="/login"]))
  end

  test "a logged-in user sees their teams, and the rest of the page", %{conn: conn} do
    user = user_fixture()
    team = App.DataFixtures.team_fixture()
    _member = App.DataFixtures.member_fixture(team, %{email: user.email, d4h_permission: 0})
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/")

    assert has_element?(lv, ~s(#start-top a[href="/teams/#{team.subdomain}"]))
    assert has_element?(lv, ~s(#start-end a[href="/teams/#{team.subdomain}"]))
    assert has_element?(lv, "#home-title")
  end

  test "the footer links to the terms and privacy pages", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#footer-terms[href="/terms"]))
    assert has_element?(lv, ~s(#footer-privacy[href="/privacy"]))
  end

  test "the footer links to the verify site", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#footer-verify[href="#{Web.VerifyHost.url()}"]))
  end

  test "the footer hides the style guide from visitors", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    refute has_element?(lv, "#footer-styles")
  end

  test "the footer hides the style guide from non-admins", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/")

    refute has_element?(lv, "#footer-styles")
  end

  test "the footer links admins to the style guide", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(is_admin: true) |> App.Repo.update!()
    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/")

    assert has_element?(lv, ~s(#footer-styles[href="/styles"]))
    assert has_element?(lv, "#footer-verify")
  end
end

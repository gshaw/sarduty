defmodule Web.HomePageLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import Phoenix.LiveViewTest

  test "a visitor sees what SAR Duty is for, and sign up and log in", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, "#home-title")
    assert has_element?(lv, ~s(.home-cta a[href="/signup"]))
    assert has_element?(lv, ~s(.home-cta a[href="/login"]))
    refute has_element?(lv, "#my-teams")
  end

  test "the page tells anyone how to verify a letter or an ID card", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#verify a[href="#{Web.VerifyHost.url()}/letters"]))
    assert has_element?(lv, ~s(#verify a[href="#{Web.VerifyHost.url()}"]))
  end

  test "a logged-in user with no team is told where access comes from", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/")

    assert has_element?(lv, "#no-teams")
    refute has_element?(lv, ".home-cta")
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

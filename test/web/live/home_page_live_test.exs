defmodule Web.HomePageLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import Phoenix.LiveViewTest

  test "renders home page", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "Welcome to"
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

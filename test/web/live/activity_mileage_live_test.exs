defmodule Web.ActivityMileageLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "redirects when not authenticated", %{conn: conn} do
    team = team_fixture(%{subdomain: "alpha"})

    assert {:error, redirect} = live(conn, ~p"/#{team.subdomain}/activities/1/mileage")

    assert {:redirect, %{to: path, flash: flash}} = redirect
    assert path == ~p"/login"
    assert %{"error" => "You must log in to access this page."} = flash
  end
end

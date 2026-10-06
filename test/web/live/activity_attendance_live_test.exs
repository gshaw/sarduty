defmodule Web.ActivityAttendanceLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "redirects when not authenticated", %{conn: conn} do
    team = team_fixture(%{subdomain: "alpha"})

    assert {:error, redirect} = live(conn, ~p"/teams/#{team}/activities/1/attendance")

    assert {:redirect, %{to: path, flash: flash}} = redirect
    assert path == ~p"/login"
    assert %{"error" => "Log in to see this page."} = flash
  end
end

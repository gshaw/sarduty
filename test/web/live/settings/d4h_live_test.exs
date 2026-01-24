defmodule Web.Settings.D4HLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest
  import App.AccountsFixtures

  test "renders D4H settings", %{conn: conn} do
    user = user_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/settings/d4h")

    assert html =~ "D4H access key"
  end
end

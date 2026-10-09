defmodule Web.Admin.IdCardsLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  test "an admin turns ID cards on and off for a team", %{conn: conn} do
    admin = user_fixture(%{is_admin: true})
    member_fixture(team_fixture(), %{email: admin.email})
    team = team_fixture(%{id_cards_enabled: false})
    conn = log_in_user(conn, admin)

    {:ok, lv, _html} = live(conn, ~p"/admin/id-cards")
    lv |> element("#id-cards-on-#{team.id}") |> render_click()
    assert Repo.reload!(team).id_cards_enabled

    lv |> element("#id-cards-off-#{team.id}") |> render_click()
    refute Repo.reload!(team).id_cards_enabled
  end

  test "a team admin who isn't a SAR Duty admin can't see it", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    assert {:error, {:redirect, %{to: "/"}}} = live(log_in_user(conn, user), ~p"/admin/id-cards")
  end
end

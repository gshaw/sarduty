defmodule Web.DemoTeamMarksTest do
  # A Try a demo team's cards and letters say Sample on the verify site, and it has no
  # Access key tab (#857).
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MemberCard
  alias App.Model.PublishedPDF

  defp verify_conn(conn) do
    conn
    |> Map.put(:host, Web.VerifyHost.host())
    |> put_req_header("fly-client-ip", "10.9.#{System.unique_integer([:positive])}")
  end

  test "a demo team's card verifies with the Sample band, a real team's without", %{conn: conn} do
    demo = team_fixture()
    demo_team_fixture(demo)
    real = team_fixture()

    for {team, sample?} <- [{demo, true}, {real, false}] do
      card = team |> member_fixture() |> member_card_fixture()
      {:ok, lv, _html} = conn |> verify_conn() |> live(~p"/#{MemberCard.format_code(card.code)}")

      assert has_element?(lv, "#result-active")
      assert has_element?(lv, "#result-sample", "Sample card") == sample?
    end
  end

  test "a demo team's letter verifies with the Sample band", %{conn: conn} do
    team = team_fixture()
    demo_team_fixture(team)

    letter =
      team
      |> member_fixture()
      |> tax_credit_letter_fixture(%{year: 2025})

    {:ok, lv, _html} =
      conn |> verify_conn() |> live(~p"/#{PublishedPDF.format_code(letter.pdf.code)}")

    assert has_element?(lv, "#result-current")
    assert has_element?(lv, "#result-sample", "Sample")
  end

  test "a demo team has no Access key tab, and its page is a 404", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    demo_team_fixture(team, %{user_id: user.id})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings")
    refute has_element?(lv, "a", "Access key")

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/settings/access-key")
    end
  end
end

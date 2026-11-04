defmodule Web.NoindexTest do
  # The X-Robots-Tag header on the pages kept out of search (#824). Which routes send it
  # is Web.RouterTest's job; these prove the pipeline reaches the response.
  use Web.ConnCase

  import App.DataFixtures

  alias App.Model.MemberCard

  setup %{conn: conn} do
    team = team_fixture()
    card = team |> member_fixture() |> member_card_fixture()
    %{card: card, verify: verify_conn(conn)}
  end

  defp verify_conn(conn) do
    conn
    |> Map.put(:host, Web.VerifyHost.host())
    |> put_req_header("fly-client-ip", "10.4.#{System.unique_integer([:positive])}")
  end

  defp robots(conn), do: get_resp_header(conn, "x-robots-tag")

  test "a card check result", %{verify: conn, card: card} do
    conn = get(conn, "/#{MemberCard.format_code(card.code)}")
    assert html_response(conn, 200)
    assert robots(conn) == ["noindex"]
  end

  test "a card photo", %{verify: conn} do
    conn = get(conn, "/SAMP-ACTV/photo")
    assert response(conn, 200)
    assert robots(conn) == ["noindex"]
  end

  test "the card check as JSON", %{verify: conn, card: card} do
    conn = get(conn, "/api/v1/cards/#{card.code}")
    assert json_response(conn, 200)
    assert robots(conn) == ["noindex"]
  end

  test "a reply link", %{conn: conn} do
    conn = get(conn, "/replies/made-up")
    assert html_response(conn, 200)
    assert robots(conn) == ["noindex"]
  end

  test "the style guide stays in search", %{conn: conn} do
    conn = get(conn, ~p"/styles")
    assert html_response(conn, 200)
    assert robots(conn) == []
  end
end

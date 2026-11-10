defmodule Web.PublishedPDFControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  alias App.Operation.PublishTaxCreditLetter

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), user: user, team: team, member: member_fixture(team)}
  end

  test "a letter downloads from the one PDF address, inline (#970)",
       %{conn: conn, team: team, member: member} do
    letter = tax_credit_letter_fixture(member)

    conn = get(conn, ~p"/teams/#{team}/pdfs/#{letter.id}")

    assert response(conn, 200) =~ "%PDF-1.7 test letter"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "inline"
  end

  test "page 1 of a published letter as a PNG the browser keeps",
       %{conn: conn, user: user, team: team, member: member} do
    {:ok, letter} = PublishTaxCreditLetter.call(team, member.id, 2025, user, nil)

    conn = get(conn, ~p"/teams/#{team}/pdfs/#{letter.id}/preview.png")

    assert <<137, "PNG", _rest::binary>> = response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["image/png"]
    assert [cache] = get_resp_header(conn, "cache-control")
    assert cache =~ "immutable"
  end

  test "a PDF that won't draw is a 404, not an error", %{conn: conn, team: team, member: member} do
    letter = tax_credit_letter_fixture(member)

    assert conn |> get(~p"/teams/#{team}/pdfs/#{letter.id}/preview.png") |> response(404)
  end

  test "a member's letter as it prints today, marked DRAFT, kept nowhere",
       %{conn: conn, team: team, member: member} do
    conn = get(conn, ~p"/teams/#{team}/tax-credit-letters/2025/members/#{member.id}/draft.png")

    assert <<137, "PNG", _rest::binary>> = response(conn, 200)
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert App.Repo.aggregate(App.Model.PublishedPDF, :count) == 0
  end
end

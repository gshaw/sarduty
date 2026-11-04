defmodule Web.CardApiLiveTest do
  use Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the page and its Markdown give the same check, with this site's verify host", %{
    conn: conn
  } do
    {:ok, lv, _html} = live(conn, ~p"/agents/id-cards")
    assert has_element?(lv, "#card-api h1", "How to check an ID card")

    assert has_element?(
             lv,
             "#card-api a[href='#{Web.VerifyHost.url()}/api/v1/cards/SAMP-ACTV']"
           )

    markdown = conn |> get(~p"/agents/id-cards.md") |> response(200)
    assert markdown =~ "GET #{Web.VerifyHost.url()}/api/v1/cards/K7Q4-M2XA"
  end

  # The doc's example is written by hand, so it could drift from what the check sends.
  test "the example has the fields of a real active card's answer", %{conn: conn} do
    [example] =
      Regex.run(~r/```json\n(.*?)```/s, Web.CardApiDoc.markdown(), capture: :all_but_first)

    answer =
      conn
      |> Map.put(:host, Web.VerifyHost.host())
      |> get("/api/v1/cards/SAMP-ACTV")
      |> json_response(200)

    assert fields(Jason.decode!(example)) == fields(answer)
  end

  test "Sample cards links each sample and shows its answer", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/agents/id-cards")

    for code <- ~w(SAMP-ACTV SAMP-RTRD SAMP-CNCD SAMP-NCRD) do
      assert has_element?(lv, "#card-api a[href='#{Web.VerifyHost.url()}/api/v1/cards/#{code}']")
    end

    assert has_element?(lv, "#card-api a[href='#{Web.VerifyHost.url()}/samples']")
    assert render(lv) =~ "&quot;status&quot;: &quot;revoked&quot;"
    assert render(lv) =~ "answers <code>404</code>"
  end

  test "Agents lists it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/agents")
    assert has_element?(lv, ~s(#agents-use-id-cards a[href="/agents/id-cards"]))
  end

  # A map's keys, nested; a list by its first item's.
  defp fields(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, fields(value)} end)
  defp fields([first | _rest]), do: [fields(first)]
  defp fields(_value), do: :value
end

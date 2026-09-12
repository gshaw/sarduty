defmodule App.Adapter.D4HTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H

  defp context do
    D4H.build_context(access_key: "key", api_host: "api.team-manager.ca.d4h.com", d4h_team_id: 1)
  end

  test "a team with no profile image has no logo to fetch" do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      assert conn.request_path == "/v3/team/1/documents"
      Req.Test.json(conn, %{"results" => []})
    end)

    assert D4H.fetch_team_image(context()) == :none
  end

  test "downloads the team's profile image" do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      case conn.request_path do
        "/v3/team/1/documents" -> Req.Test.json(conn, %{"results" => [%{"id" => 7}]})
        "/v3/team/1/documents/7/download" -> Plug.Conn.send_resp(conn, 200, "png bytes")
      end
    end)

    assert D4H.fetch_team_image(context()) == {:ok, "png bytes", "team.png"}
  end
end

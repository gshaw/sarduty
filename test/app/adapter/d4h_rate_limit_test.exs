defmodule App.Adapter.D4HRateLimitTest do
  # Apart from D4HTest because a 429 writes an event, which needs the database.
  use App.DataCase

  import ExUnit.CaptureLog

  alias App.Adapter.D4H
  alias App.Model.Event
  alias App.Model.Team

  test "records a 429 that Req's retry then gets past" do
    team = %Team{id: nil, d4h_access_key: "key", d4h_api_host: "api.ca.d4h.org", d4h_team_id: 1}
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      if Agent.get_and_update(attempts, &{&1, &1 + 1}) == 0 do
        conn
        |> Plug.Conn.put_resp_header("retry-after", "0")
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"title" => "Too Many Requests"})
      else
        Req.Test.json(conn, %{"results" => [], "totalSize" => 0})
      end
    end)

    log =
      capture_log(fn ->
        head = team |> D4H.build_context_from_team() |> D4H.fetch_list_head("/members")
        assert head == %{total_size: 0, newest_updated_at: nil}
      end)

    assert log =~ "D4H rate limit (429)"
    assert Agent.get(attempts, & &1) == 2

    assert %Event{data: %{"path" => "/v3/team/1/members", "retry_after" => "0"}} =
             Event.get_last(:d4h_rate_limited)
  end
end

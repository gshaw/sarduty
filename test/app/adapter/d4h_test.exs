defmodule App.Adapter.D4HTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

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

  describe "lists" do
    # Tags on `page` of a list of `total`, 1000 to a page, numbered from 0.
    defp tag_page(conn, total, short_by \\ 0) do
      conn = Plug.Conn.fetch_query_params(conn)
      page = String.to_integer(conn.query_params["page"])
      first = page * 1000
      last = min(first + 1000, total - short_by) - 1
      results = for id <- first..last//1, do: %{"id" => id, "title" => "Tag #{id}"}
      Req.Test.json(conn, %{"results" => results, "totalSize" => total})
    end

    test "fetches every page and keeps them in order" do
      Req.Test.stub(App.Adapter.D4H, &tag_page(&1, 4500))

      tags = D4H.fetch_tags(context())

      assert length(tags) == 4500
      assert Enum.map(tags, & &1.d4h_tag_id) == Enum.to_list(0..4499)
    end

    test "raises when D4H returns fewer rows than its total" do
      Req.Test.stub(App.Adapter.D4H, &tag_page(&1, 2500, 600))

      assert_raise D4H.Error, ~r/1900 of 2500/, fn -> D4H.fetch_tags(context()) end
    end

    test "an error on a later page raises with D4H's status" do
      Req.Test.stub(App.Adapter.D4H, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        if conn.query_params["page"] == "2",
          do: conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"title" => "Forbidden"}),
          else: tag_page(conn, 3500)
      end)

      error = assert_raise D4H.Error, fn -> D4H.fetch_tags(context()) end
      assert error.status == 403
    end

    test "a list's head is its total and newest change" do
      Req.Test.stub(App.Adapter.D4H, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["sort"] == "updatedAt"
        assert conn.query_params["order"] == "desc"
        assert conn.query_params["size"] == "1"

        Req.Test.json(conn, %{
          "results" => [%{"id" => 1, "updatedAt" => "2026-10-05T12:00:00.123Z"}],
          "totalSize" => 189
        })
      end)

      assert D4H.fetch_list_head(context(), "/members") ==
               %{total_size: 189, newest_updated_at: ~U[2026-10-05 12:00:00Z]}
    end

    test "changed attendance stops at the first row older than the cursor" do
      row = fn id, updated_at ->
        %{
          "id" => id,
          "activity" => %{"resourceType" => "Event", "id" => 9},
          "member" => %{"resourceType" => "Member", "id" => 1},
          "startsAt" => "2026-10-01T10:00:00Z",
          "endsAt" => "2026-10-01T12:00:00Z",
          "duration" => 120,
          "status" => "ATTENDING",
          "updatedAt" => updated_at
        }
      end

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["page"] == "0"

        Req.Test.json(conn, %{
          "results" => [
            row.(3, "2026-10-06T09:00:00Z"),
            row.(2, "2026-10-06T08:00:00Z"),
            row.(1, "2026-10-01T08:00:00Z")
          ],
          "totalSize" => 3000
        })
      end)

      rows = D4H.fetch_attendances_changed_since(context(), ~U[2026-10-06 07:55:00Z])
      assert Enum.map(rows, & &1.d4h_attendance_id) == [3, 2]
    end
  end

  test "logs a 429 that Req's retry then gets past" do
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
        assert D4H.fetch_list_head(context(), "/members") == %{
                 total_size: 0,
                 newest_updated_at: nil
               }
      end)

    assert log =~ "D4H rate limit (429)"
    assert log =~ "/v3/team/1/members"
    assert Agent.get(attempts, & &1) == 2
  end
end

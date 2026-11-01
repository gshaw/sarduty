defmodule App.Adapter.D4HTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H

  defp context do
    D4H.build_context(access_key: "key", api_host: "api.team-manager.ca.d4h.com", d4h_team_id: 1)
  end

  describe "the whiteboard (#515)" do
    defp whiteboard_context(api_host),
      do: D4H.build_context(access_key: "key", api_host: api_host, d4h_team_id: 1)

    test "reads every note, the newest first, from D4H and from Records" do
      for host <- ["api.ca.d4h.org", D4H.records_host()] do
        Req.Test.stub(App.Adapter.D4H, fn conn ->
          conn = Plug.Conn.fetch_query_params(conn)
          assert conn.request_path == "/v3/team/1/whiteboard"
          assert %{"sort" => "createdAt", "order" => "desc", "size" => "1000"} = conn.query_params

          Req.Test.json(conn, %{
            "results" => [
              %{"id" => 2, "text" => "Live", "owner" => %{"resourceType" => "Team"}},
              %{"id" => 1, "text" => "Old", "owner" => %{"resourceType" => "Organisation"}}
            ],
            "totalSize" => 2
          })
        end)

        context = whiteboard_context(host)

        assert {:ok, [%{text: "Live", owner_kind: :team}, %{owner_kind: :organization}]} =
                 D4H.fetch_whiteboard_notes(context)
      end
    end

    test "a 403 is the module off, and any other failure raises" do
      Req.Test.stub(App.Adapter.D4H, fn conn ->
        conn
        |> Plug.Conn.put_status(403)
        |> Req.Test.json(%{"title" => "Forbidden"})
      end)

      context = whiteboard_context("api.ca.d4h.org")
      assert D4H.fetch_whiteboard_notes(context) == :off

      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 401, ""))
      assert_raise D4H.Error, fn -> D4H.fetch_whiteboard_notes(context) end
    end
  end

  describe "fetch_whoami (#537)" do
    defp whoami, do: fetch_whoami([])

    defp fetch_whoami(opts),
      do: D4H.fetch_whoami([access_key: "key", api_host: "api.ca.d4h.org"] ++ opts)

    test "a 401, a 403, or no team is a refused key" do
      for status <- [401, 403] do
        Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, status, ""))
        assert whoami() == {:error, :refused}
      end

      Req.Test.stub(App.Adapter.D4H, &Req.Test.json(&1, %{"members" => []}))
      assert whoami() == {:error, :refused}
    end

    # #727: the account whoami has no rights, so a check that read only it saw none.
    test "the key's rights come from the team's whoami, and Records sends none" do
      member = %{
        "id" => 70,
        "name" => "SAR Duty",
        "owner" => %{"resourceType" => "Team", "id" => 7}
      }

      rights = %{"Team" => %{"READ" => true}}

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        case conn.request_path do
          "/v3/whoami" -> Req.Test.json(conn, %{"account" => %{}, "members" => [member]})
          "/v3/team/7/whoami" -> Req.Test.json(conn, %{"context" => %{"permissions" => rights}})
        end
      end)

      assert {:ok, %{permissions: ^rights}} = whoami()
      assert {:ok, %{permissions: ^rights}} = fetch_whoami(d4h_team_id: 7)
      assert {:ok, %{permissions: nil}} = fetch_whoami(d4h_team_id: 8)

      records = D4H.fetch_whoami(access_key: "key", api_host: D4H.records_host())
      assert {:ok, %{permissions: nil}} = records
    end

    test "an outage is D4H not answering, not a bad key" do
      for status <- [500, 503] do
        Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, status, ""))
        assert whoami() == {:error, :unreachable}
      end

      Req.Test.stub(App.Adapter.D4H, &Req.Test.transport_error(&1, :timeout))
      assert whoami() == {:error, :unreachable}
    end
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

  test "lists award certificates, and downloads one with its type" do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.request_path do
        "/v3/team/1/documents" ->
          assert conn.query_params["target_resource_type"] == "MemberQualificationAward"

          Req.Test.json(conn, %{
            "results" => [%{"id" => 7, "targetResource" => %{"id" => 55}}],
            "totalSize" => 1
          })

        "/v3/team/1/documents/7/download" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/pdf", nil)
          |> Plug.Conn.send_resp(200, "%PDF")
      end
    end)

    assert [%{d4h_document_id: 7, d4h_target_id: 55}] = D4H.fetch_award_documents(context())
    assert D4H.fetch_document(context(), 7) == {:ok, "%PDF", "application/pdf"}
  end

  test "uploads a certificate to an award, seen only by the team's admins" do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      assert {conn.method, conn.request_path} == {"POST", "/v3/team/1/documents"}
      conn = Plug.Parsers.call(conn, Plug.Parsers.init(parsers: [:multipart]))

      assert %{
               "title" => "First Aid certificate",
               "targetResourceType" => "MemberQualificationAward",
               "targetResourceId" => "55",
               "restricted" => "RESTRICTED",
               "file" => %Plug.Upload{filename: "first-aid.pdf", content_type: "application/pdf"}
             } = conn.body_params

      Req.Test.json(conn, %{"id" => 9, "targetResource" => %{"id" => 55}})
    end)

    file = %{
      title: "First Aid certificate",
      bytes: "%PDF",
      filename: "first-aid.pdf",
      content_type: "application/pdf"
    }

    assert {:ok, %{d4h_document_id: 9, d4h_target_id: 55}} =
             D4H.upload_document(context(), 55, file)
  end

  test "reads one member's awards" do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.request_path == "/v3/team/1/member-qualification-awards"
      assert conn.query_params["member_id"] == "7"

      Req.Test.json(conn, %{
        "results" => [
          %{
            "id" => 3,
            "member" => %{"resourceType" => "Member", "id" => 7},
            "qualification" => %{"id" => 4},
            "startsAt" => "2026-10-01T07:00:00.000Z",
            "endsAt" => nil
          }
        ],
        "totalSize" => 1
      })
    end)

    assert [%{d4h_award_id: 3, d4h_member_id: 7, d4h_qualification_id: 4}] =
             D4H.fetch_member_awards(context(), 7)
  end

  describe "services" do
    test "a team is on Records only at Records' host" do
      assert D4H.service(%App.Model.Team{d4h_api_host: "records.sarduty.com"}) == :records
      assert D4H.service(%App.Model.Team{d4h_api_host: "api.ca.d4h.org"}) == :d4h
      assert D4H.records?("records.sarduty.com")
      refute D4H.records?("api.d4h.org")
    end

    test "the approved list is every D4H region, then Records" do
      hosts = D4H.service_hosts()
      assert List.last(hosts) == "records.sarduty.com"
      assert D4H.regions() |> Map.values() |> Enum.all?(&(&1 in hosts))
      assert length(hosts) == map_size(D4H.regions()) + 1
    end

    test "the words people read name the service" do
      assert D4H.service_name(:records) == "SAR Duty Records"
      assert D4H.key_name("records.sarduty.com") == "Records access key"
      assert D4H.key_name("api.ca.d4h.org") == "D4H access key"
    end

    test "an error names who refused or did not answer" do
      refused = %D4H.Error{status: 403, message: "Forbidden (403)"}
      assert D4H.error_text(:d4h, refused) == "D4H refused it: Forbidden (403)"

      down = %D4H.Error{status: 503, message: "Service Unavailable (503)"}
      assert D4H.error_text(:records, down) == "SAR Duty Records did not answer. Try again."

      timeout = %Req.TransportError{reason: :timeout}
      assert D4H.error_text(:d4h, timeout) == "D4H did not answer. Try again."
    end

    test "every team unpublishes in SAR Duty" do
      assert D4H.unpublish_text(:d4h) == "Unpublish it with Change activity first."
      refute D4H.unpublish_text(:d4h) =~ "D4H"
      refute D4H.unpublish_text(:records) =~ "Records"
    end
  end

  describe "one activity and its attendance (#33)" do
    defp refuse(conn, status, title),
      do: conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{"title" => title})

    test "fetches an activity" do
      Req.Test.stub(App.Adapter.D4H, fn conn ->
        assert conn.request_path == "/v3/team/1/exercises/7"

        Req.Test.json(conn, %{
          "id" => 7,
          "owner" => %{"resourceType" => "Team", "id" => 1},
          "startsAt" => "2026-10-01T18:00:00Z",
          "endsAt" => "2026-10-01T21:00:00Z",
          "tags" => []
        })
      end)

      assert {:ok, %D4H.Activity{d4h_activity_id: 7}} =
               D4H.fetch_activity(context(), 7, "exercise")
    end

    test "an activity D4H has not got, or a refused key, is an error" do
      for {status, title} <- [{404, "Not Found"}, {401, "Unauthorized"}],
          kind <- ["event", "incident", "exercise"] do
        Req.Test.stub(App.Adapter.D4H, &refuse(&1, status, title))

        assert {:error, %D4H.Error{status: ^status} = error} =
                 D4H.fetch_activity(context(), 7, kind)

        assert Exception.message(error) == "#{title} (#{status})"
      end
    end

    test "fetches an activity's attendance" do
      Req.Test.stub(App.Adapter.D4H, &Req.Test.json(&1, %{"results" => [], "totalSize" => 0}))

      assert D4H.fetch_activity_attendance(context(), 7, []) == {:ok, []}
    end

    test "attendance D4H has not got, or a refused key, is an error" do
      for {status, title} <- [{404, "Not Found"}, {401, "Unauthorized"}] do
        Req.Test.stub(App.Adapter.D4H, &refuse(&1, status, title))

        assert {:error, %D4H.Error{status: ^status}} =
                 D4H.fetch_activity_attendance(context(), 7, [])
      end
    end
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
               %{total_size: 189, newest_updated_at: ~U[2026-10-05 12:00:00.123Z]}
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
end

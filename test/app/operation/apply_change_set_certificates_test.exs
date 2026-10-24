defmodule App.Operation.ApplyChangeSetCertificatesTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Operation.ApplyChangeSet

  # A certificate's set (#493): the award, then the file on the award it made.

  @now ~U[2026-10-24 17:00:00.000000Z]
  @document %{bytes: "%PDF", filename: "first-aid.pdf", content_type: "application/pdf"}

  setup do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    member = member_fixture(team)
    qualification = qualification_fixture(team, %{title: "First Aid"})

    rows = [
      %ChangeSetRow{
        action: :award_qualification,
        member_id: member.id,
        old_value: %{},
        new_value: %{
          "title" => "First Aid",
          "d4h_qualification_id" => qualification.d4h_qualification_id,
          "d4h_member_id" => member.d4h_member_id,
          "starts_at" => "2026-10-01T07:00:00Z",
          "ends_at" => "2029-10-01T07:00:00Z"
        }
      },
      %ChangeSetRow{
        action: :attach_award_document,
        member_id: member.id,
        old_value: %{},
        new_value: %{"title" => "First Aid", "created_in_set" => true}
      }
    ]

    set = ChangeSet.propose!(%ChangeSet{team_id: team.id, source: :certificates}, rows)
    %{user: user, team: team, set: set}
  end

  defp stub_d4h(upload_status) do
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")
      send(test_pid, {:d4h, conn.method, path})

      case {conn.method, path} do
        {"GET", "/member-qualification-awards"} ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        {"POST", "/member-qualification-awards"} ->
          Req.Test.json(conn, %{
            "id" => 300,
            "member" => %{"id" => 1},
            "qualification" => %{"id" => 2}
          })

        {"POST", "/documents"} ->
          conn = Plug.Parsers.call(conn, Plug.Parsers.init(parsers: [:multipart]))
          send(test_pid, {:upload, conn.body_params["targetResourceId"]})

          conn
          |> Plug.Conn.put_status(upload_status)
          |> Req.Test.json(%{"id" => 900, "title" => "Unprocessable Entity"})
      end
    end)
  end

  defp apply_set(ctx) do
    set = Repo.reload!(ctx.set)
    ApplyChangeSet.call(ctx.team, set, ctx.user, @now, document: @document)
  end

  test "the file goes on the award the set made", ctx do
    stub_d4h(200)

    assert {:ok, [award, document]} = apply_set(ctx)
    assert {award.status, award.d4h_record_id} == {:applied, 300}
    assert {document.status, document.d4h_record_id} == {:applied, 900}
    assert document.new_value["d4h_award_id"] == 300
    assert_received {:upload, "300"}
  end

  test "a failed upload is sent again on the same award, never a second award", ctx do
    stub_d4h(422)
    assert {:ok, [%{status: :applied}, %{status: :failed}]} = apply_set(ctx)
    assert posts() == ["/member-qualification-awards", "/documents"]

    stub_d4h(200)
    assert {:ok, [%{status: :applied, d4h_record_id: 900}]} = apply_set(ctx)
    assert posts() == ["/documents"]
    assert_received {:upload, "300"}
  end

  # D4H keeps an award's start at midnight UTC; the set's starts at midnight here.
  test "an award D4H has from the same day is not sent again, nor its file", ctx do
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      send(test_pid, {:d4h, conn.method, conn.request_path})

      Req.Test.json(conn, %{
        "results" => [
          %{
            "id" => 8,
            "member" => %{"id" => 1},
            "qualification" => %{"id" => hd(ctx.set.rows).new_value["d4h_qualification_id"]},
            "startsAt" => "2026-10-01T00:00:00.000Z",
            "endsAt" => nil
          }
        ],
        "totalSize" => 1
      })
    end)

    assert {:ok, [%{status: :skipped}, %{status: :failed}]} = apply_set(ctx)
    refute_received {:d4h, "POST", _path}
  end

  defp posts do
    receive do
      {:d4h, "POST", path} -> [path | posts()]
      {:d4h, _method, _path} -> posts()
    after
      0 -> []
    end
  end
end

defmodule App.AttendanceStub do
  @moduledoc """
  Stands in for D4H in tests of a reply (#444), through the adapter's `Req.Test` stub:
  a draft activity holding these attendance rows, taken from the copy. A PATCH answers
  with the row and its new status, and the test receives `{:d4h_write, d4h_id, body}`.
  """

  alias App.Model.Attendance

  def stub(rows) do
    test = self()
    d4h_rows = Map.new(rows, &{&1.d4h_attendance_id, json(&1)})

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")

      case {conn.method, path} do
        {"GET", "/attendance"} ->
          Req.Test.json(conn, %{
            "results" => Map.values(d4h_rows),
            "totalSize" => map_size(d4h_rows)
          })

        {"GET", _activity} ->
          Req.Test.json(conn, %{"published" => false})

        {"PATCH", "/attendance/" <> id} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          body = Jason.decode!(body)
          id = String.to_integer(id)
          send(test, {:d4h_write, id, body})
          Req.Test.json(conn, Map.merge(d4h_rows[id], body))
      end
    end)
  end

  defp json(%Attendance{} = row) do
    row = App.Repo.preload(row, [:member, :activity])

    %{
      "id" => row.d4h_attendance_id,
      "activity" => %{"resourceType" => "Exercise", "id" => row.activity.d4h_activity_id},
      "member" => %{"resourceType" => "Member", "id" => row.member.d4h_member_id},
      "status" => String.upcase(row.status),
      "startsAt" => DateTime.to_iso8601(row.started_at),
      "endsAt" => DateTime.to_iso8601(row.finished_at)
    }
  end
end

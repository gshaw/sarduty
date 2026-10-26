defmodule App.AttendanceStub do
  @moduledoc """
  Stands in for D4H in tests of a reply (#444), through the adapter's `Req.Test` stub:
  a draft activity holding these attendance rows, taken from the copy. A PATCH answers
  with the row and its new status, and the test receives `{:d4h_write, d4h_id, body}`.
  A POST adds a row (#564), and the test receives `{:d4h_write, :create, body}`; D4H
  refuses one for a member in `refuse:`, their D4H member ids.
  """

  alias App.Model.Attendance

  def stub(rows, opts \\ []) do
    test = self()
    refuse = Keyword.get(opts, :refuse, [])
    d4h_rows = Map.new(rows, &{&1.d4h_attendance_id, json(&1)})

    Req.Test.stub(App.Adapter.D4H, &answer(&1, test, d4h_rows, refuse))
  end

  defp answer(conn, test, d4h_rows, refuse) do
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
        {body, conn} = read_json(conn)
        id = String.to_integer(id)
        send(test, {:d4h_write, id, body})
        Req.Test.json(conn, Map.merge(d4h_rows[id], body))

      {"POST", "/attendance"} ->
        {body, conn} = read_json(conn)
        send(test, {:d4h_write, :create, body})
        created(conn, body, body["memberId"] in refuse)
    end
  end

  defp read_json(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(body), conn}
  end

  defp created(conn, _body, true = _refused),
    do: conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "Down"})

  defp created(conn, body, false) do
    Req.Test.json(conn, %{
      "id" => System.unique_integer([:positive]),
      "activity" => %{"resourceType" => "Exercise", "id" => body["activityId"]},
      "member" => %{"resourceType" => "Member", "id" => body["memberId"]},
      "status" => body["status"],
      "startsAt" => body["startsAt"],
      "endsAt" => body["endsAt"]
    })
  end

  # A row from the copy, or one only D4H has: a struct with its member and activity.
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

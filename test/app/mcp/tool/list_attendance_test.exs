defmodule App.MCP.Tool.ListAttendanceTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.ListAttendance
  alias App.Model.Activity

  @hours_tags %{primary: "Primary Hours", secondary: "Secondary Hours", other: nil}
  @now ~U[2026-03-10 12:00:00Z]

  defp activity(started_at) do
    %Activity{
      id: 7,
      title: "Training night",
      activity_kind: "exercise",
      tags: ["Primary Hours"],
      started_at: started_at,
      finished_at: DateTime.add(started_at, 150, :minute),
      is_published: true,
      address: "1 Secret Road",
      description: "Meet at the gate"
    }
  end

  defp row(id, name, status, started_at, opts \\ []) do
    %{
      id: id,
      member_id: id * 10,
      member_name: name,
      status: status,
      started_at: started_at,
      finished_at: started_at && DateTime.add(started_at, 120, :minute),
      duration_in_minutes: opts[:duration] || 120,
      replied_at: opts[:replied_at]
    }
  end

  test "a past activity's rows are attended or absent, with times and minutes" do
    start = ~U[2026-03-02 02:00:00Z]
    rows = [row(2, "Sam", "absent", start), row(1, "Alex", "attending", start)]

    output =
      start |> activity() |> ListAttendance.build(rows, @hours_tags, "America/Vancouver", @now)

    assert output["activity"]["hours"] == "primary"
    assert output["activity"]["minutes"] == 150
    assert output["activity"]["published"]
    assert [alex, sam] = output["rows"]
    assert {alex["status"], sam["status"]} == {"attended", "absent"}
    assert alex["started_at"] == "2026-03-01T18:00:00-08:00"
    assert alex["minutes"] == 120
    refute inspect(output) =~ "Secret"
    refute inspect(output) =~ "gate"
  end

  test "a coming activity's rows use the reply words" do
    start = ~U[2026-03-20 02:00:00Z]

    rows = [
      row(1, "Alex", "attending", start),
      row(2, "Sam", "absent", start),
      row(3, "Pat", "requested", start)
    ]

    output = start |> activity() |> ListAttendance.build(rows, @hours_tags, "Etc/UTC", @now)
    statuses = Map.new(output["rows"], &{&1["member_name"], &1["status"]})

    assert statuses == %{"Alex" => "signed_up", "Sam" => "cant_make_it", "Pat" => "no_reply"}
  end

  test "a member's 2 rows both show, and a row without times keeps D4H's minutes" do
    start = ~U[2026-03-02 02:00:00Z]
    rows = [row(1, "Alex", "attending", start), row(2, "Alex", "attending", nil, duration: 45)]

    output = start |> activity() |> ListAttendance.build(rows, @hours_tags, "Etc/UTC", @now)

    assert [%{"attendance_id" => 2, "minutes" => 45}, %{"attendance_id" => 1}] = output["rows"]
  end
end

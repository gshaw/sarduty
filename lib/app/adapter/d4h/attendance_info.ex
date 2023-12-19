defmodule App.Adapter.D4H.AttendanceInfo do
  defstruct d4h_attendance_id: nil,
            d4h_activity_id: nil,
            d4h_member_id: nil,
            started_at: nil,
            finished_at: nil,
            duration_in_minutes: nil,
            status: nil

  def build(record) do
    {:ok, started_at, 0} = DateTime.from_iso8601(record["date"])
    {:ok, finished_at, 0} = DateTime.from_iso8601(record["enddate"])

    %__MODULE__{
      d4h_attendance_id: record["id"],
      d4h_activity_id: record["activity"]["id"],
      d4h_member_id: record["member"]["id"],
      started_at: started_at,
      finished_at: finished_at,
      duration_in_minutes: record["duration"],
      status: record["status"]
    }
  end
end

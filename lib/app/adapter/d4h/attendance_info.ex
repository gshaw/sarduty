defmodule App.Adapter.D4H.AttendanceInfo do
  defstruct attendance_id: nil,
            activity_id: nil,
            member_id: nil,
            started_at: nil,
            finished_at: nil,
            duration_in_minutes: nil,
            status: nil

  def build(record) do
    {:ok, started_at, 0} = DateTime.from_iso8601(record["date"])
    {:ok, finished_at, 0} = DateTime.from_iso8601(record["enddate"])

    %__MODULE__{
      attendance_id: record["id"],
      activity_id: record["activity"]["id"],
      member_id: record["member"]["id"],
      started_at: started_at,
      finished_at: finished_at,
      duration_in_minutes: record["duration"],
      status: record["status"]
    }
  end
end

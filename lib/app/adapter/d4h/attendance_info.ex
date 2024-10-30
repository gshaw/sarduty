defmodule App.Adapter.D4H.AttendanceInfo do
  alias App.Adapter.D4H.Parse

  defstruct d4h_attendance_id: nil,
            d4h_activity_id: nil,
            d4h_member_id: nil,
            started_at: nil,
            finished_at: nil,
            duration_in_minutes: nil,
            status: nil

  def build(record) do
    {:ok, d4h_activity_id, _kind} = Parse.activity(record["activity"])

    %__MODULE__{
      d4h_attendance_id: record["id"],
      d4h_activity_id: d4h_activity_id,
      d4h_member_id: Parse.member_id(record["member"]),
      started_at: Parse.datetime(record["startsAt"]),
      finished_at: Parse.datetime(record["endsAt"]),
      duration_in_minutes: record["duration"],
      status: String.downcase(record["status"])
    }
  end
end

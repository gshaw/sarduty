defmodule Service.D4H.Attendance do
  defstruct d4h_attendance_id: nil,
            d4h_activity_id: nil,
            member: nil

  def build(record, team_members) do
    d4h_member_id = record["member"]["id"]
    member = Enum.find(team_members, fn r -> r.d4h_member_id == d4h_member_id end)

    %__MODULE__{
      d4h_attendance_id: record["id"],
      d4h_activity_id: record["activity"]["id"],
      # d4h_member_id: d4h_member_id,
      member: member
    }
  end
end

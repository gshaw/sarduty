defmodule App.Adapter.D4H.Attendance do
  alias App.Adapter.D4H

  defstruct d4h_attendance_id: nil,
            d4h_activity_id: nil,
            status: nil,
            member: nil

  def build(record, team_members) do
    d4h_member_id = record["member"]["id"]
    member = Enum.find(team_members, fn r -> r.d4h_member_id == d4h_member_id end)

    %__MODULE__{
      d4h_attendance_id: record["id"],
      d4h_activity_id: record["activity"]["id"],
      status: record["status"],
      member:
        member ||
          %D4H.Member{
            d4h_member_id: record["member"]["id"],
            d4h_team_id: record["member"]["team_id"],
            name: record["member"]["name"]
          }
    }
  end
end

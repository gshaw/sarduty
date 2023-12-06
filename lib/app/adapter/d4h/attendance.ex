defmodule App.Adapter.D4H.Attendance do
  alias App.Adapter.D4H

  defstruct attendance_id: nil,
            activity_id: nil,
            status: nil,
            member: nil

  def build(record, team_members) do
    member_id = record["member"]["id"]
    member = Enum.find(team_members, fn r -> r.member_id == member_id end)

    %__MODULE__{
      attendance_id: record["id"],
      activity_id: record["activity"]["id"],
      status: record["status"],
      member:
        member ||
          %D4H.Member{
            member_id: record["member"]["id"],
            team_id: record["member"]["team_id"],
            name: record["member"]["name"]
          }
    }
  end
end

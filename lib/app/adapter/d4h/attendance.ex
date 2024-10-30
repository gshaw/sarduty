defmodule App.Adapter.D4H.Attendance do
  alias App.Adapter.D4H
  alias App.Adapter.D4H.Parse

  defstruct d4h_attendance_id: nil,
            d4h_activity_id: nil,
            status: nil,
            member: nil

  def build(record, team_members) do
    d4h_member_id = Parse.member_id(record["member"])
    member = Enum.find(team_members, fn r -> r.d4h_member_id == d4h_member_id end)

    {:ok, d4h_activity_id, _kind} = Parse.activity(record["activity"])

    %__MODULE__{
      d4h_attendance_id: record["id"],
      d4h_activity_id: d4h_activity_id,
      status: String.downcase(record["status"]),
      member:
        member ||
          %D4H.Member{
            d4h_member_id: d4h_member_id,
            d4h_team_id: Parse.team_id(record["owner"])
            # name: record["member"]["name"]
          }
    }
  end
end

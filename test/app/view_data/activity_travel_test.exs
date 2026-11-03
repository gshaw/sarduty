defmodule App.ViewData.ActivityTravelTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Team
  alias App.Model.Trip
  alias App.ViewData.ActivityTravel

  @team %Team{
    subdomain: "coastrange",
    d4h_api_host: "api.ca.d4h.org",
    timezone: "America/Vancouver"
  }
  @activity %Activity{
    ref_id: "01472",
    title: "Missing hiker",
    activity_kind: "incident",
    d4h_activity_id: 372_944
  }

  defp row(id, name, started_at, finished_at) do
    %{
      attendance: %Attendance{
        id: id,
        d4h_attendance_id: 100 + id,
        started_at: started_at,
        finished_at: finished_at
      },
      member: %Member{name: name},
      activity_km: 50,
      yard_km: 80
    }
  end

  # Oct 30, 14:00 to 18:30 Vancouver time, and the next morning.
  defp report do
    %{
      rows: [
        row(1, "Ann", ~U[2026-10-30 21:00:00Z], ~U[2026-10-31 01:30:00Z]),
        row(2, "Bob", ~U[2026-10-30 21:00:00Z], ~U[2026-10-31 02:00:00Z]),
        row(3, "Bob", ~U[2026-10-31 15:00:00Z], nil)
      ],
      yard_to_activity_km: 20
    }
  end

  test "rows split into set and not set, by D4H attendance id" do
    view = ActivityTravel.build(report(), %{101 => %Trip{travel: "icp", km: 50}})

    assert Enum.map(view.set, & &1.attendance.id) == [1]
    assert Enum.map(view.not_set, & &1.attendance.id) == [2, 3]
  end

  test "the copy for D4H names the activity, lists each row set, and the rows to leave alone" do
    view =
      ActivityTravel.build(report(), %{
        101 => %Trip{travel: "icp", km: 50},
        103 => %Trip{travel: "other", km: 140}
      })

    prompt = ActivityTravel.d4h_prompt(view, @team, @activity)

    assert prompt =~ ~s(activity 01472, "Missing hiker":\n)
    assert prompt =~ "https://coastrange.team-manager.ca.d4h.com/team/incidents/view/372944\n"
    assert prompt =~ "Don't save."
    assert prompt =~ "Ann | Oct 30, 14:00 to Oct 30, 18:30 | 50\n"
    assert prompt =~ "Bob | From Oct 31, 08:00 | 140\n"

    assert String.ends_with?(
             prompt,
             "Leave the Mileage km box alone on these rows:\nBob | Oct 30, 14:00 to Oct 30, 19:00"
           )
  end
end

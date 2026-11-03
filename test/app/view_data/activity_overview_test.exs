defmodule App.ViewData.ActivityOverviewTest do
  use App.DataCase

  import App.DataFixtures

  alias App.ViewData.ActivityOverview

  # Each chart's report runs, so a mistake in one can't drop it from Overview unseen.
  test "an incident that started has sign-ups by day" do
    team = team_fixture()
    started_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
    activity = activity_fixture(team, %{activity_kind: "incident", started_at: started_at})
    replied_at = DateTime.add(started_at, -1, :hour)

    for name <- ["Ann", "Bob"] do
      member = member_fixture(team, %{name: name})
      attendance_fixture(activity, member, %{replied_at: replied_at, duration_in_minutes: 120})
    end

    charts = ActivityOverview.charts(team, activity, DateTime.utc_now(), true)

    assert Enum.map(charts, & &1.id) == ["chart-sign-ups"]
  end

  test "a coming activity with no replies has no charts" do
    team = team_fixture()
    activity = activity_fixture(team, %{started_at: DateTime.add(DateTime.utc_now(), 3, :day)})
    attendance_fixture(activity, member_fixture(team), %{status: "requested"})

    assert ActivityOverview.charts(team, activity, DateTime.utc_now(), true) == []
  end
end

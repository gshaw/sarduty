defmodule App.Operation.BuildMileageReportTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H
  alias App.Operation.BuildMileageReport

  defp record(d4h_member_id, name, status) do
    %D4H.Attendance{
      status: status,
      member: %D4H.Member{d4h_member_id: d4h_member_id, name: name, address: "#{name}'s house"}
    }
  end

  defp routes(to_activity, to_yard),
    do: %{coordinate: {49.1, -122.8}, to_activity: to_activity, to_yard: to_yard}

  test "round trips are twice one way, in whole km and hours to a tenth" do
    # 12.3 km and 25 minutes one way: 24.6 km rounds to 25, 50 minutes is 0.8 hours.
    # 40.0 km and 45 minutes one way: 80 km, 1.5 hours.
    report =
      BuildMileageReport.build(
        [record(1, "Ann", "attending")],
        %{1 => routes({12_300, 1500}, {40_000, 2700})},
        {7_400, 600}
      )

    assert [ann] = report.attendees
    assert {ann.activity_km, ann.activity_hours} == {25, 0.8}
    assert {ann.yard_km, ann.yard_hours} == {80, 1.5}
    assert {report.yard_to_activity_km, report.yard_to_activity_hours} == {15, 0.3}
  end

  test "lists only attending members, by name" do
    records = [
      record(1, "Zoe", "attending"),
      record(2, "Bob", "absent"),
      record(3, "Ann", "attending"),
      record(4, "Cat", "requested")
    ]

    routes = %{1 => routes({1000, 60}, {1000, 60}), 3 => routes({1000, 60}, {1000, 60})}

    report = BuildMileageReport.build(records, routes, {1000, 60})

    assert Enum.map(report.attendees, & &1.name) == ["Ann", "Zoe"]
  end

  test "a route Mapbox couldn't find is blank, and the rest still count" do
    records = [record(1, "Ann", "attending"), record(2, "Bob", "attending")]

    routes = %{
      1 => routes(nil, {40_000, 2700}),
      2 => %{coordinate: "unknown", to_activity: nil, to_yard: nil}
    }

    report = BuildMileageReport.build(records, routes, nil)

    assert [ann, bob] = report.attendees
    assert {ann.activity_km, ann.activity_hours, ann.yard_km} == {nil, nil, 80}
    assert {bob.coordinate, bob.activity_km, bob.yard_km} == {"unknown", nil, nil}
    assert report.yard_to_activity_km == nil
  end
end

defmodule App.Operation.BuildMileageReportTest do
  use ExUnit.Case, async: true

  alias App.Model.Attendance
  alias App.Model.HomeCoordinate
  alias App.Model.Member
  alias App.Operation.BuildMileageReport

  @activity "49.30000,-123.35000"
  @yard "49.20000,-123.10000"
  @ann_home "49.25000,-123.00000"

  defp member(id, name, address \\ "1 Main St"), do: %Member{id: id, name: name, address: address}

  defp row(id, member),
    do: %Attendance{
      id: id,
      member_id: member.id,
      member: member,
      started_at: ~U[2026-10-30 21:00:00Z]
    }

  describe "build" do
    test "round trips are twice one way, in whole km" do
      ann = member(1, "Ann")
      # 12.3 km one way to the activity rounds 24.6 to 25; 40 km to the yard is 80.
      distances = %{
        {@activity, @ann_home} => 12_300,
        {@yard, @ann_home} => 40_000,
        {@yard, @activity} => 7_400
      }

      report =
        BuildMileageReport.build([row(10, ann)], %{1 => @ann_home}, distances, @activity, @yard)

      assert [%{activity_km: 25, yard_km: 80, two_rows?: false}] = report.rows
      assert report.yard_to_activity_km == 15
    end

    test "no route or no home leaves that km blank, and the rest still count" do
      ann = member(1, "Ann")
      bob = member(2, "Bob", nil)
      distances = %{{@activity, @ann_home} => nil, {@yard, @ann_home} => 40_000}
      homes = %{1 => @ann_home, 2 => :no_address}

      report =
        BuildMileageReport.build([row(10, ann), row(11, bob)], homes, distances, @activity, @yard)

      assert [ann_row, bob_row] = report.rows
      assert {ann_row.activity_km, ann_row.yard_km} == {nil, 80}
      assert {bob_row.home, bob_row.activity_km, bob_row.yard_km} == {:no_address, nil, nil}
      assert report.yard_to_activity_km == nil
    end

    test "a member with two rows has both, marked so a page can tell them apart" do
      ann = member(1, "Ann")
      distances = %{{@activity, @ann_home} => 10_000}

      report =
        BuildMileageReport.build(
          [row(10, ann), row(11, ann)],
          %{1 => @ann_home},
          distances,
          @activity,
          nil
        )

      assert [%{two_rows?: true, activity_km: 20}, %{two_rows?: true, activity_km: 20}] =
               report.rows
    end
  end

  describe "pairs" do
    test "from the activity and the yard to each home found, and the yard to the activity" do
      pairs = BuildMileageReport.pairs([@ann_home, :not_found, @ann_home], @activity, @yard)

      assert Enum.sort(pairs) ==
               Enum.sort([{@activity, @ann_home}, {@yard, @ann_home}, {@yard, @activity}])
    end

    test "a team with no yard asks only from the activity" do
      assert BuildMileageReport.pairs([@ann_home], @activity, nil) == [{@activity, @ann_home}]
    end
  end

  describe "homes_to_look_up" do
    test "a home never looked up, or looked up from another address" do
      ann = member(1, "Ann", "1 Main St")
      bob = member(2, "Bob", "2 Oak Ave")
      cat = member(3, "Cat", "3 Elm St")
      dan = member(4, "Dan", "  ")

      saved = %{
        1 => %HomeCoordinate{address: "1 Main St", coordinate: @ann_home},
        2 => %HomeCoordinate{address: "9 Old Rd", coordinate: @ann_home}
      }

      assert BuildMileageReport.homes_to_look_up([ann, bob, cat, dan], saved) == [bob, cat]
    end
  end
end

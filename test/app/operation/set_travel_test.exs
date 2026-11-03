defmodule App.Operation.SetTravelTest do
  use ExUnit.Case, async: true

  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Operation.SetTravel

  # Ann: 50 km round trip to the ICP, 80 to the yard. Bob: no route to either.
  defp rows do
    [
      %{
        attendance: %Attendance{id: 1, d4h_attendance_id: 101},
        member: %Member{name: "Ann"},
        activity_km: 50,
        yard_km: 80
      },
      %{
        attendance: %Attendance{id: 2, d4h_attendance_id: 102},
        member: %Member{name: "Bob"},
        activity_km: nil,
        yard_km: nil
      }
    ]
  end

  defp kms({:ok, plan}), do: Enum.map(plan.sets, &{&1.member.name, &1.travel, &1.km})

  test "ICP and yard set the saved round trip" do
    assert kms(SetTravel.plan(rows(), [1], "icp", "")) == [{"Ann", "icp", 50}]
    assert kms(SetTravel.plan(rows(), [1], "yard", "")) == [{"Ann", "yard", 80}]
  end

  test "a passenger counts 0 km, route or not" do
    assert kms(SetTravel.plan(rows(), [1, 2], "passenger", "")) ==
             [{"Ann", "passenger", 0}, {"Bob", "passenger", 0}]
  end

  test "typed km set every checked row, and must be a whole number from 0" do
    assert kms(SetTravel.plan(rows(), [1, 2], "other", " 140 ")) ==
             [{"Ann", "other", 140}, {"Bob", "other", 140}]

    for typed <- ["", "12.5", "-3", "abc"],
        do: assert(SetTravel.plan(rows(), [1], "other", typed) == {:error, :bad_km})
  end

  test "a row with no route to where it drove is skipped, so the admin types its km" do
    assert {:ok, plan} = SetTravel.plan(rows(), [1, 2], "icp", "")
    assert [%{member: %{name: "Bob"}}] = plan.skipped

    assert SetTravel.result_text(plan) ==
             "1 row set to ICP. No route from Bob's home to the ICP, so type their km."
  end

  test "nothing checked, an id the page didn't show, or an unknown travel sets nothing" do
    assert SetTravel.plan(rows(), [], "icp", "") == {:error, :nothing_checked}
    assert SetTravel.plan(rows(), [99], "icp", "") == {:error, :nothing_checked}
    assert SetTravel.plan(rows(), [1], "bus", "") == {:error, :bad_travel}
  end

  test "the toast names the km typed" do
    {:ok, plan} = SetTravel.plan(rows(), [1, 2], "other", "140")
    assert SetTravel.result_text(plan) == "2 rows set to 140 km."
  end
end

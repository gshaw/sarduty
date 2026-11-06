defmodule App.Operation.SetTravelTest do
  use ExUnit.Case, async: true

  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Trip
  alias App.Operation.SetTravel

  # Ann: 50 km round trip to the ICP, 80 to the yard. Bob: no route to either.
  defp rows do
    [
      %{
        attendance: %Attendance{id: 1, d4h_attendance_id: 101},
        member: %Member{id: 11, name: "Ann"},
        activity_km: 50,
        yard_km: 80
      },
      %{
        attendance: %Attendance{id: 2, d4h_attendance_id: 102},
        member: %Member{id: 12, name: "Bob"},
        activity_km: nil,
        yard_km: nil
      }
    ]
  end

  defp kms({:ok, plan}), do: Enum.map(plan.sets, &{&1.member.name, &1.travel, &1.km})

  test "a team admin's change clears Confirmed for each member who has it, but their own" do
    [ann, bob] = rows()
    confirmed = %Trip{checked_at: ~U[2026-11-01 10:00:00Z]}
    ann = Map.put(ann, :trip, confirmed)
    bob = Map.put(bob, :trip, %Trip{})

    assert [%Member{name: "Ann"}] = SetTravel.clears_confirmed([ann, bob], nil)
    assert SetTravel.clears_confirmed([ann, bob], 11) == []
    assert SetTravel.clears_confirmed([Map.put(ann, :trip, nil)], nil) == []
  end

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

  test "a row with no route to where it drove is skipped, and the toast names them" do
    assert {:ok, plan} = SetTravel.plan(rows(), [1, 2], "icp", "")
    assert [%{member: %{name: "Bob"}}] = plan.skipped

    assert SetTravel.result_text(plan) ==
             "Saved Ann's travel. No route to the ICP for Bob, so nothing changed for them."

    assert SetTravel.ok?(plan)
  end

  # Saving again would ask the member to confirm again.
  test "a row with that travel and km already is unchanged, not set again" do
    [ann, bob] = rows()
    ann = Map.put(ann, :trip, %Trip{travel: "icp", km: 50})
    bob = Map.put(bob, :trip, %Trip{travel: "icp", km: 70})

    # Bob has no route now, so his saved km stands.
    assert {:ok, plan} = SetTravel.plan([ann, bob], [1, 2], "icp", "")
    assert plan.sets == [] and plan.skipped == []
    assert length(plan.unchanged) == 2
    assert SetTravel.result_text(plan) == "Nothing changed."
    assert SetTravel.ok?(plan)

    assert kms(SetTravel.plan([%{ann | activity_km: 54}], [1], "icp", "")) ==
             [{"Ann", "icp", 54}]

    assert kms(SetTravel.plan([ann], [1], "other", "50")) == [{"Ann", "other", 50}]
  end

  test "clear takes the rows set, and nothing set is nothing changed" do
    [ann, bob] = rows()
    ann = Map.put(ann, :trip, %Trip{travel: "icp", km: 50})
    bob = Map.put(bob, :trip, nil)

    assert {:ok, plan} = SetTravel.plan([ann, bob], [1, 2], "clear", "")
    assert [%{member: %{name: "Ann"}}] = plan.cleared
    assert SetTravel.result_text(plan) == "Cleared Ann's travel."

    assert {:ok, plan} = SetTravel.plan([ann, bob], [2], "clear", "")
    assert SetTravel.result_text(plan) == "Nothing changed."
  end

  test "the toast counts members, and a member with two rows once" do
    [ann, bob] = rows()
    ann2 = %{ann | attendance: %Attendance{id: 3, d4h_attendance_id: 103}}

    {:ok, plan} = SetTravel.plan([ann, ann2], [1, 3], "passenger", "")
    assert SetTravel.result_text(plan) == "Saved Ann's travel."

    {:ok, plan} = SetTravel.plan([ann, ann2, bob], [1, 2, 3], "passenger", "")
    assert SetTravel.result_text(plan) == "Saved 2 members' travel."
  end

  test "when no checked row has a route, the toast names them, as an error" do
    assert {:ok, plan} = SetTravel.plan(rows(), [2], "icp", "")
    refute SetTravel.ok?(plan)

    assert SetTravel.result_text(plan) ==
             "No route to the ICP for Bob. Change their rows and choose Other."
  end

  test "nothing checked, an id the page didn't show, or an unknown travel sets nothing" do
    assert SetTravel.plan(rows(), [], "icp", "") == {:error, :nothing_checked}
    assert SetTravel.plan(rows(), [99], "icp", "") == {:error, :nothing_checked}
    assert SetTravel.plan(rows(), [1], "bus", "") == {:error, :bad_travel}
  end
end

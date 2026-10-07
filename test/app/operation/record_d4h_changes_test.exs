defmodule App.Operation.RecordD4HChangesTest do
  use ExUnit.Case, async: true

  alias App.Operation.RecordD4HChanges

  describe "diff/3" do
    test "an unchanged record is no change" do
      member = %{name: "Jane", position: "Member", d4h_status: "OPERATIONAL", email: "a@b"}
      assert RecordD4HChanges.diff(:member, member, member) == nil
    end

    test "names changed fields and keeps their old and new values" do
      old = %{status: "ABSENT", started_at: nil, finished_at: nil, duration_in_minutes: 0}

      new = %{
        old
        | status: "ATTENDING",
          started_at: ~U[2026-10-03 02:02:00Z],
          duration_in_minutes: 0
      }

      assert RecordD4HChanges.diff(:attendance, old, new) == %{
               action: :changed,
               fields: ["status", "started_at"],
               old_value: %{"status" => "ABSENT", "started_at" => nil},
               new_value: %{"status" => "ATTENDING", "started_at" => "2026-10-03T02:02:00Z"}
             }
    end

    test "names a contact detail change but never keeps its values" do
      old = %{name: "Jane", phone: "604 555 0100", email: "jane@example.com"}
      new = %{old | phone: "604 555 0199"}

      assert %{fields: ["phone"], old_value: old_value, new_value: new_value} =
               RecordD4HChanges.diff(:member, old, new)

      assert old_value == %{}
      assert new_value == %{}
    end

    test "ignores fields it doesn't track" do
      old = %{title: "Training", description: "Old", tags: ["A"], updated_at: 1}
      new = %{old | description: "New", updated_at: 2}
      assert RecordD4HChanges.diff(:activity, old, new) == nil
    end

    test "an added record keeps its tracked values" do
      award = %{starts_at: ~U[2026-01-01 08:00:00Z], ends_at: nil, d4h_award_id: 9}

      assert RecordD4HChanges.diff(:award, nil, award) == %{
               action: :added,
               fields: [],
               old_value: nil,
               new_value: %{"starts_at" => "2026-01-01T08:00:00Z", "ends_at" => nil}
             }
    end

    test "a removed group membership has no values" do
      assert %{action: :removed, old_value: %{}} =
               RecordD4HChanges.diff(:group_membership, %{group_id: 1}, nil)
    end
  end
end

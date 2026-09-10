defmodule App.Model.TeamTest do
  use ExUnit.Case, async: true

  alias App.Model.Team

  describe "refresh_state/1" do
    test "reads a stage's progress as refreshing" do
      assert Team.refresh_state("Refreshing") == :refreshing
      assert Team.refresh_state("Group Memberships: 120/300 (40%)") == :refreshing
    end

    test "reads an error as failed, even when D4H's reason names a stage" do
      result = "Error: D4H API error (403): Members [read] permission required"

      assert Team.refresh_state(result) == :failed
    end

    test "tells a team that never refreshed from one that did" do
      assert Team.refresh_state(nil) == :never
      assert Team.refresh_state("OK") == :ok
    end
  end
end

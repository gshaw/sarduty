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

  describe "names (#738)" do
    @team %Team{name: "Ridge SAR", legal_name: "Ridge SAR", abbreviated_name: "Ridge SAR"}

    test "saving fails only over each name's maximum, not its advice" do
      params = %{
        name: String.duplicate("a", 50),
        legal_name: String.duplicate("a", 100),
        abbreviated_name: String.duplicate("a", 20)
      }

      assert Team.build_settings_changeset(@team, params).valid?

      changeset =
        Team.build_settings_changeset(@team, %{
          name: String.duplicate("a", 51),
          legal_name: String.duplicate("a", 101),
          abbreviated_name: String.duplicate("a", 21)
        })

      assert changeset.errors |> Keyword.keys() |> Enum.sort() == [
               :abbreviated_name,
               :legal_name,
               :name
             ]
    end

    test "every name is required" do
      changeset = Team.build_settings_changeset(@team, %{legal_name: "", abbreviated_name: ""})
      assert changeset.errors |> Keyword.keys() |> Enum.sort() == [:abbreviated_name, :legal_name]
    end

    test "too long goes by the advice, and the legal name has none" do
      assert Team.name_too_long?(%{name: String.duplicate("a", 21)}, :name)
      refute Team.name_too_long?(%{name: String.duplicate("a", 20)}, :name)
      assert Team.name_too_long?(%{abbreviated_name: "Ridge SAR!!"}, :abbreviated_name)
      refute Team.name_too_long?(%{legal_name: String.duplicate("a", 100)}, :legal_name)
    end
  end

  test "the subdomain new is reserved for Add a team (#512)" do
    changeset = Team.build_changeset(%Team{}, %{subdomain: "new"})
    assert {"This subdomain is reserved. Use another.", _opts} = changeset.errors[:subdomain]
    refute Team.build_changeset(%Team{}, %{subdomain: "newton"}).errors[:subdomain]
  end
end

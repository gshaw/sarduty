defmodule App.Operation.UpdateTeamSettingsTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias App.Adapter.D4H.WhoAmI
  alias App.Model.Team
  alias App.Operation.UpdateTeamSettings

  @now ~U[2026-09-10 12:00:00.000000Z]
  @team %Team{name: "Ridge Valley SAR", d4h_team_id: 7, d4h_access_key: "old-key"}

  defp check(lookup) do
    @team
    |> Team.build_settings_changeset(%{"new_d4h_access_key" => " new-key "})
    |> UpdateTeamSettings.check_new_key(@team, lookup, @now)
  end

  test "saves a key whose member is on this team, and when" do
    changeset = check({:ok, %WhoAmI{d4h_team_ids: [3, 7]}})

    assert changeset.valid?
    assert get_change(changeset, :d4h_access_key) == "new-key"
    assert get_change(changeset, :d4h_access_key_saved_at) == @now
  end

  test "rejects a key for a different D4H team" do
    changeset = check({:ok, %WhoAmI{d4h_team_ids: [3]}})

    refute changeset.valid?
    assert {"belongs to a different D4H team", _} = changeset.errors[:new_d4h_access_key]
    refute get_change(changeset, :d4h_access_key)
  end

  test "rejects a key D4H doesn't recognize" do
    changeset = check({:error, "Unable to determine team ID"})

    assert {"is unknown or not authorized", _} = changeset.errors[:new_d4h_access_key]
    refute get_change(changeset, :d4h_access_key)
  end

  test "says so when D4H doesn't respond" do
    changeset = check({:error, :unreachable})

    assert {"could not be checked. D4H did not respond", _} =
             changeset.errors[:new_d4h_access_key]
  end

  test "a blank key field is not a new key" do
    changeset = Team.build_settings_changeset(@team, %{"new_d4h_access_key" => "  "})

    refute get_change(changeset, :new_d4h_access_key)
    refute get_change(changeset, :d4h_access_key)
  end

  test "the settings form can't change the D4H team or the saved key" do
    params = %{"d4h_team_id" => "99", "d4h_access_key" => "posted", "name" => "Renamed"}
    changeset = Team.build_settings_changeset(@team, params)

    assert changeset.changes == %{name: "Renamed"}
  end
end

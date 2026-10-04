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
    whoami = %WhoAmI{
      d4h_team_ids: [3, 7],
      member_names: %{3 => "Sam", 7 => "SAR Duty"},
      member_ids: %{3 => 30, 7 => 70}
    }

    changeset = check({:ok, whoami})

    assert changeset.valid?
    assert get_change(changeset, :d4h_access_key) == "new-key"
    assert get_change(changeset, :d4h_access_key_saved_at) == @now
    assert get_change(changeset, :d4h_access_key_owner) == "SAR Duty"
    assert get_change(changeset, :d4h_access_key_member_id) == 70
  end

  test "rejects a key for a different D4H team" do
    changeset = check({:ok, %WhoAmI{d4h_team_ids: [3]}})

    refute changeset.valid?

    assert {"Use a D4H access key for this team. This one is for another team.", _} =
             changeset.errors[:new_d4h_access_key]

    refute get_change(changeset, :d4h_access_key)
  end

  test "rejects a key D4H doesn't recognize" do
    changeset = check({:error, "Unable to determine team ID"})

    assert {"Paste the key again. D4H does not accept this one.", _} =
             changeset.errors[:new_d4h_access_key]

    refute get_change(changeset, :d4h_access_key)
  end

  test "says so when D4H doesn't respond" do
    changeset = check({:error, :unreachable})

    assert {"D4H did not respond. Try again in a few minutes.", _} =
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

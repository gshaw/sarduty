defmodule App.Operation.SaveTeamKeyTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias App.Adapter.D4H.WhoAmI
  alias App.Model.Team
  alias App.Operation.SaveTeamKey

  @now ~U[2026-09-10 12:00:00.000000Z]
  @team %Team{
    name: "Ridge Valley SAR",
    legal_name: "Ridge Valley Search and Rescue Society",
    abbreviated_name: "RIDGE",
    d4h_team_id: 7,
    d4h_access_key: "old-key",
    d4h_sync_state: %{"heads" => %{}, "key_rejected" => true}
  }

  defp check(lookup) do
    @team
    |> Team.build_key_changeset(%{"new_d4h_access_key" => " new-key "})
    |> SaveTeamKey.check_new_key(@team, lookup, @now)
  end

  test "saves a key whose member is on this team, when, and what D4H lets it do" do
    permissions = %{"MemberGroup" => %{"UPDATE" => true}}

    whoami = %WhoAmI{
      d4h_team_ids: [3, 7],
      member_names: %{3 => "Sam", 7 => "SAR Duty"},
      member_ids: %{3 => 30, 7 => 70},
      permissions: permissions
    }

    changeset = check({:ok, whoami})

    assert changeset.valid?
    assert get_change(changeset, :d4h_access_key) == "new-key"
    assert get_change(changeset, :d4h_access_key_saved_at) == @now
    assert get_change(changeset, :d4h_access_key_owner) == "SAR Duty"
    assert get_change(changeset, :d4h_access_key_member_id) == 70
    assert get_change(changeset, :d4h_sync_state) == %{"heads" => %{}}
    assert get_change(changeset, :d4h_permissions) == permissions
    assert get_change(changeset, :d4h_permissions_checked_at) == @now
  end

  test "rejects a key for a different D4H team" do
    changeset = check({:ok, %WhoAmI{d4h_team_ids: [3]}})

    refute changeset.valid?

    assert {"Use a D4H access key for this team. This one is for another team.", _} =
             changeset.errors[:new_d4h_access_key]

    refute get_change(changeset, :d4h_access_key)
  end

  test "rejects a key D4H doesn't recognize" do
    changeset = check({:error, :refused})

    assert {"Paste the key again. D4H refused this one.", _} =
             changeset.errors[:new_d4h_access_key]

    refute get_change(changeset, :d4h_access_key)
  end

  test "says so when D4H doesn't respond" do
    changeset = check({:error, :unreachable})

    assert {"D4H did not answer. Try again in a few minutes.", _} =
             changeset.errors[:new_d4h_access_key]
  end

  test "a blank key field asks for a key" do
    changeset = Team.build_key_changeset(@team, %{"new_d4h_access_key" => "  "})

    refute changeset.valid?
    assert {"Paste the new key.", _} = changeset.errors[:new_d4h_access_key]
  end

  test "the General form can't change the D4H team or the key" do
    params = %{
      "d4h_team_id" => "99",
      "d4h_access_key" => "posted",
      "new_d4h_access_key" => "typed",
      "name" => "Renamed"
    }

    changeset = Team.build_settings_changeset(@team, params)

    assert changeset.changes == %{name: "Renamed"}
  end
end

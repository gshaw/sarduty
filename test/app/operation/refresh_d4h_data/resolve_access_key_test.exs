defmodule App.Operation.RefreshD4HData.ResolveAccessKeyTest do
  use ExUnit.Case, async: true

  alias App.Accounts.User
  alias App.Model.Team
  alias App.Operation.RefreshD4HData.ResolveAccessKey

  defp user(id, key), do: %User{id: id, email: "user#{id}@example.com", d4h_access_key: key}

  test "the team's own key comes first" do
    team = %Team{d4h_access_key: "team-key"}

    assert ResolveAccessKey.key_owner(team, [user(1, "personal")]) == :team
  end

  test "without a team key, the earliest member with a personal key is borrowed" do
    team = %Team{d4h_access_key: nil}
    users = [user(9, "later"), user(2, nil), user(4, "earliest")]

    assert %User{id: 4} = ResolveAccessKey.key_owner(team, users)
  end

  test "a blank key doesn't count" do
    team = %Team{d4h_access_key: ""}

    assert ResolveAccessKey.key_owner(team, [user(1, "")]) == nil
  end
end

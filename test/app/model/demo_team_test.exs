defmodule App.Model.DemoTeamTest do
  use App.DataCase, async: true

  alias App.AccountsFixtures
  alias App.DataFixtures
  alias App.Model.DemoTeam
  alias App.Model.Member
  alias App.Model.Team

  describe "logging in to a demo team (#857)" do
    setup do
      visitor = AccountsFixtures.user_fixture()
      team = DataFixtures.member_logins_team_fixture()
      DataFixtures.demo_team_fixture(team, %{user_id: visitor.id})
      DataFixtures.manager_fixture(team, %{email: visitor.email})
      %{team: team, visitor: visitor}
    end

    test "its visitor manages it", %{team: team, visitor: visitor} do
      assert [%Team{id: id}] = visitor.email |> String.upcase() |> Team.get_managed_by(now())
      assert id == team.id
    end

    test "an email a visitor typed onto an Owner gets nothing", %{team: team} do
      DataFixtures.manager_fixture(team, %{email: "real.admin@sfsar.ca"})

      assert Team.get_managed_by("real.admin@sfsar.ca", now()) == []
      assert Member.get_logins("real.admin@sfsar.ca", now()) == []
    end

    test "an email a visitor typed onto a member gets nothing", %{team: team} do
      DataFixtures.member_fixture(team, %{email: "someone@example.org"})

      assert Member.get_logins("someone@example.org", now()) == []
    end

    test "a demo whose visitor is gone lets nobody in" do
      other = DataFixtures.member_logins_team_fixture()
      DataFixtures.demo_team_fixture(other)
      DataFixtures.manager_fixture(other, %{email: "left@example.org"})

      assert Team.get_managed_by("left@example.org", now()) == []
    end
  end

  describe "a demo's second team (#963)" do
    test "is a demo, closed to every login, and out of the real teams" do
      visitor = AccountsFixtures.user_fixture()
      coast = DataFixtures.member_logins_team_fixture()
      basin = DataFixtures.member_logins_team_fixture()
      real = DataFixtures.team_fixture()
      DataFixtures.demo_team_fixture(coast, %{user_id: visitor.id, second_team_id: basin.id})
      DataFixtures.manager_fixture(basin, %{email: visitor.email})

      assert DemoTeam.demo?(basin)
      assert DemoTeam.for_team(basin) == nil
      assert Team.get_managed_by(visitor.email, now()) == []
      assert Enum.map(Team.get_all_real(), & &1.id) == [real.id]
    end
  end

  defp now, do: DateTime.utc_now()
end

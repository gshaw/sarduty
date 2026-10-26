defmodule App.Operation.SetTeamMCPTest do
  use App.DataCase

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.Operation.SetTeamMCP

  test "a team admin or a SAR Duty admin turns MCP on; anyone else cannot" do
    %{user: team_admin, team: team} = user_with_team_fixture()
    stranger = AccountsFixtures.user_fixture()
    admin = make_admin(AccountsFixtures.user_fixture())

    assert SetTeamMCP.call(team, true, stranger) == {:error, :not_allowed}
    assert {:ok, %{mcp_enabled: true}} = SetTeamMCP.call(team, true, team_admin)
    assert {:ok, %{mcp_enabled: false}} = SetTeamMCP.call(team, false, admin)
  end
end

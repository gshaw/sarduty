defmodule App.Operation.CheckTeamKey do
  @moduledoc """
  Who the team's key belongs to and what D4H lets it do (#727), read again from D4H's
  whoami. Access key's Check again calls it, and so does every full refresh.
  `{:ok, team}`, or `{:error, :refused}` or `{:error, :unreachable}` from D4H.
  """

  alias App.Adapter.D4H
  alias App.Adapter.D4H.WhoAmI
  alias App.Model.Team

  def call(%Team{} = team) do
    case D4H.fetch_whoami(
           access_key: team.d4h_access_key,
           api_host: team.d4h_api_host,
           d4h_team_id: team.d4h_team_id
         ) do
      {:ok, whoami} -> Team.update(team, changes(whoami, team.d4h_team_id, DateTime.utc_now()))
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Pure. The team's key fields from `whoami`, checked at `now`."
  def changes(%WhoAmI{} = whoami, d4h_team_id, now) do
    %{
      d4h_access_key_owner: WhoAmI.member_name(whoami, d4h_team_id),
      d4h_access_key_member_id: WhoAmI.member_id(whoami, d4h_team_id),
      d4h_permissions: whoami.permissions,
      d4h_permissions_checked_at: now
    }
  end
end

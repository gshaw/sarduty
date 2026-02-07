defmodule App.Operation.ResolveD4HContext do
  @moduledoc """
  Temporary module to resolve a D4H API context for a team.

  Prefers the team's own PAT (`d4h_access_key`), but falls back to the first
  user on the team that has one. This allows background refreshes to keep
  working while teams are being migrated to team-level PATs.

  TODO: Remove this module once all teams have their own `d4h_access_key`.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Repo

  @spec call(Team.t()) :: {:ok, Req.Request.t()} | {:error, :no_access_key}
  def call(%Team{} = team) do
    cond do
      team.d4h_access_key ->
        {:ok, D4H.build_context_from_team(team)}

      user = find_user_with_pat(team) ->
        {:ok, D4H.build_context_from_user(user)}

      true ->
        {:error, :no_access_key}
    end
  end

  defp find_user_with_pat(team) do
    User
    |> where([u], u.team_id == ^team.id and not is_nil(u.d4h_access_key))
    |> limit(1)
    |> Repo.one()
    |> maybe_preload_team(team)
  end

  defp maybe_preload_team(nil, _team), do: nil

  defp maybe_preload_team(user, team) do
    %{user | team: team}
  end
end

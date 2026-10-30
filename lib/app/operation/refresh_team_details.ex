defmodule App.Operation.RefreshTeamDetails do
  @moduledoc """
  Team settings' Refresh: the team's place and time zone again from D4H. The names
  are the team's own, so Refresh leaves them (#738).
  `{:ok, team}`, `{:error, text}` when D4H refuses or doesn't answer, or
  `{:error, changeset}`.
  """

  alias App.Adapter.D4H
  alias App.Model.Team

  def call(%Team{} = team) do
    case team |> D4H.build_context_from_team() |> D4H.fetch_team() do
      {:ok, d4h_team} -> Team.update(team, plan(team, d4h_team))
      {:error, error} -> {:error, D4H.error_text(team, error)}
    end
  end

  @doc "The team's new fields. A team with no place on its D4H record keeps the one it has."
  def plan(%Team{} = team, %D4H.Team{} = d4h_team) do
    {lat, lng} = d4h_team.coordinate || {team.lat, team.lng}
    %{lat: lat, lng: lng, timezone: d4h_team.timezone}
  end
end

defmodule App.Operation.SetTeamFeature do
  @moduledoc """
  Turns one of a team's features on or off. A team admin does it on team settings'
  Features tab, where each switch saves when flipped.

  - `:member_logins` (#156). Off ends access at once: a member's next page is a 404,
    since every member page checks it.
  - `:chores` (#341) and `:certificates` (#493), which show only while member logins
    are on. Each keeps its value while member logins are off.
  - `:whiteboard` (#515). Once it's on, the page calls read_whiteboard/1, so its notes
    show at once and the page can say when D4H has the module off.

  MCP has its own, App.Operation.SetTeamMCP: turning it off revokes every token.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.RefreshD4HData.UpsertWhiteboardNotes
  alias App.Repo

  require Logger

  @fields %{
    member_logins: :member_logins,
    chores: :chores_enabled,
    certificates: :certificates_enabled,
    whiteboard: :whiteboard_enabled
  }

  def features, do: Map.keys(@fields)

  @doc "`{:ok, team}`."
  def call(%Team{} = team, feature, enabled, %User{} = user)
      when is_map_key(@fields, feature) and is_boolean(enabled) do
    {:ok, team} =
      Repo.transaction(fn ->
        team = team |> Ecto.Changeset.change([{@fields[feature], enabled}]) |> Repo.update!()
        {kind, data} = event(feature, enabled)
        Event.record!(kind, team_id: team.id, user_id: user.id, data: data)
        team
      end)

    {:ok, team}
  end

  defp event(:member_logins, true), do: {:member_logins_turned_on, %{}}
  defp event(:member_logins, false), do: {:member_logins_turned_off, %{}}
  defp event(feature, true), do: {:feature_turned_on, %{feature: feature}}
  defp event(feature, false), do: {:feature_turned_off, %{feature: feature}}

  @doc """
  Reads the whiteboard from D4H for a team that just turned it on, and returns the team
  with `d4h_whiteboard` as the read found it. A failed read leaves it as it was: the next
  sync or the night's refresh reads it.
  """
  def read_whiteboard(%Team{d4h_access_key: key} = team) when key not in [nil, ""] do
    team |> D4H.build_context_from_team() |> UpsertWhiteboardNotes.call(team)
  rescue
    error in D4H.Error ->
      Logger.warning("Whiteboard read failed for team #{team.id}: #{Exception.message(error)}")
      team
  end

  def read_whiteboard(team), do: team
end

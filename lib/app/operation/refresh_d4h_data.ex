defmodule App.Operation.RefreshD4HData do
  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Operation.RefreshD4HData
  alias App.Repo

  def call(current_user) do
    team = current_user.team
    d4h = D4H.build_context_from_user(current_user)
    save_team_logo(d4h, team)
    RefreshD4HData.UpsertMembers.call(d4h, team)

    d4h_tag_index = build_d4h_tag_index(d4h)
    RefreshD4HData.UpsertActivities.call(d4h, team, d4h_tag_index, "exercises")
    RefreshD4HData.UpsertActivities.call(d4h, team, d4h_tag_index, "events")
    RefreshD4HData.UpsertActivities.call(d4h, team, d4h_tag_index, "incidents")
    RefreshD4HData.UpsertAttendances.call(d4h, team)
    update_team_refreshed_at(team)
  end

  defp build_d4h_tag_index(d4h) do
    d4h
    |> D4H.fetch_tags()
    |> Enum.map(fn r -> {r.d4h_tag_id, r.title} end)
    |> Map.new()
  end

  defp update_team_refreshed_at(team) do
    changeset = Team.build_changeset(team, %{d4h_refreshed_at: DateTime.utc_now()})
    Repo.update!(changeset)
  end

  defp save_team_logo(d4h, team) do
    case D4H.fetch_team_image(d4h) do
      {:ok, data, _filename} ->
        logo_path = Team.logo_path(team.subdomain)
        logo_dir_path = Path.dirname(logo_path)
        File.mkdir_p!(logo_dir_path)
        File.write!(logo_path, data)
    end
  end
end

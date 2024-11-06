defmodule App.Operation.RefreshD4HData do
  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Operation.RefreshD4HData
  alias App.Repo

  def call(current_user) do
    d4h = D4H.build_context_from_user(current_user)
    save_team_logo(d4h, current_user.team)
    RefreshD4HData.Members.call(d4h, current_user.team_id)
    RefreshD4HData.Activities.call(d4h, current_user.team_id)
    RefreshD4HData.Attendances.call(d4h, current_user.team_id)
    update_team_refreshed_at(current_user.team)
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

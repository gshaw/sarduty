defmodule App.Operation.RefreshD4HData do
  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Operation.RefreshD4HData
  alias App.Repo

  def call(current_user) do
    d4h = D4H.build_context(current_user)
    RefreshD4HData.Members.call(d4h, current_user.team_id)
    RefreshD4HData.Activities.call(d4h, current_user.team_id)
    RefreshD4HData.Attendances.call(d4h, current_user.team_id)

    update_team_refreshed_at(current_user.team)
  end

  defp update_team_refreshed_at(team) do
    changeset = Team.build_changeset(team, %{d4h_refreshed_at: DateTime.utc_now()})
    Repo.update!(changeset)
  end
end

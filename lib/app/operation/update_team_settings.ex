defmodule App.Operation.UpdateTeamSettings do
  alias App.Model.Team
  alias App.Repo

  @doc "Saves the General tab's names. The key is on Access key, App.Operation.SaveTeamKey."
  def call(%Team{} = team, params) do
    team |> Team.build_settings_changeset(params) |> Repo.update()
  end
end

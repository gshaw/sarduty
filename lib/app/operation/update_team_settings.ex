defmodule App.Operation.UpdateTeamSettings do
  alias App.Model.Team
  alias App.Repo

  @doc """
  Saves the General tab: the team's names and its address. The key is on Access key,
  App.Operation.SaveTeamKey, and who signs on Signer, App.Operation.SaveTeamSigner.
  """
  def call(%Team{} = team, params) do
    team |> Team.build_settings_changeset(params) |> Repo.update()
  end
end

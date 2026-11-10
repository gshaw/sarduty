defmodule App.Operation.SaveTeamSigner do
  @moduledoc """
  Saves team settings' Signer tab (#995): who signs the team's tax credit letters, with
  their title, phone, and email. Letters sign with the name typed, "/s/ Alex Chen", so
  there's no picture to upload. The address is on General.
  """

  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, team}` or `{:error, changeset}`."
  def call(%Team{} = team, params),
    do: team |> Team.build_signer_changeset(params) |> Repo.update()
end

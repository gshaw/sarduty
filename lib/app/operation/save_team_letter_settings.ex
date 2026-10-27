defmodule App.Operation.SaveTeamLetterSettings do
  @moduledoc """
  Saves team settings' Tax credit letters tab: the mailing address and who signs. The
  signature is App.Operation.SaveTeamSignature's.
  """

  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, team}` or `{:error, changeset}`."
  def call(%Team{} = team, params),
    do: team |> Team.build_letters_changeset(params) |> Repo.update()
end

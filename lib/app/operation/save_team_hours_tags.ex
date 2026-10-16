defmodule App.Operation.SaveTeamHoursTags do
  @moduledoc """
  Saves the hours tags a team names for itself (#323): the ones its organization leaves
  blank. A team admin does this on the team's hours tags settings page.
  """

  alias App.Model.Activity
  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, team}`, or `{:error, changeset}` for the form."
  def call(%Team{} = team, params) do
    team
    |> Team.build_hours_tags_changeset(Activity.organization_hours_tags(team), params)
    |> Repo.update()
  end
end

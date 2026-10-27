defmodule App.Operation.SaveTeamMemberSettings do
  @moduledoc """
  Saves team settings' Members tab: the Retiring group (#514) and the attendance check
  (#366). The Retiring group must be one of the team's groups without rules, since a rule
  such as "Standing is Active" on it would take out every member. The one saved stays
  allowed after D4H deletes it, so saving the attendance check never clears it quietly.
  """

  import Ecto.Changeset

  alias App.Model.Group
  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, team}` or `{:error, changeset}`."
  def call(%Team{} = team, params) do
    team
    |> Team.build_members_changeset(params)
    |> validate_retiring_group(team)
    |> Repo.update()
  end

  @doc "The groups the Retiring group can be: those without rules, by title."
  def retiring_choices(%Team{} = team), do: Group.get_kept_by_hand(team.id)

  defp validate_retiring_group(changeset, team) do
    case get_change(changeset, :retiring_d4h_group_id) do
      nil ->
        changeset

      id ->
        allowed = team |> retiring_choices() |> Enum.map(& &1.d4h_group_id)

        if id in allowed or id == team.retiring_d4h_group_id,
          do: changeset,
          else: add_error(changeset, :retiring_d4h_group_id, "Select a group without rules.")
    end
  end
end

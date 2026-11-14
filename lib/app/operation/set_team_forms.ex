defmodule App.Operation.SetTeamForms do
  @moduledoc """
  Turns team forms on or off for a team (#1083): the team keeps its own forms, filled
  in from its activities, as an organization does. Only a SAR Duty admin does it, on the
  team's admin page, /admin/teams/:id, so a team tries forms that still need work while
  every other team sees nothing. Team settings' Features tab shows it only once on.
  Turning it off hides the team's forms and keeps them, with every PDF published from
  them, so turning it back on brings them back as they were.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, team}`, or `{:error, :not_allowed}` for someone who isn't a SAR Duty admin."
  def call(%Team{} = team, enabled, %User{} = user) when is_boolean(enabled) do
    if user.is_admin, do: set(team, enabled, user), else: {:error, :not_allowed}
  end

  defp set(team, enabled, user) do
    Repo.transaction(fn ->
      team = team |> Ecto.Changeset.change(forms_enabled: enabled) |> Repo.update!()
      kind = if enabled, do: :team_forms_turned_on, else: :team_forms_turned_off
      Event.record!(kind, team_id: team.id, user_id: user.id)
      team
    end)
  end
end

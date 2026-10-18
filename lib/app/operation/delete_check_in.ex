defmodule App.Operation.DeleteCheckIn do
  @moduledoc """
  Deletes a check-in recorded by mistake (#366), found through the team. The member's
  attendance clock goes back to what it was without it.
  """

  alias App.Model.MemberCheckIn
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, check_in_id) do
    MemberCheckIn
    |> Repo.get_by!(id: check_in_id, team_id: team.id)
    |> Repo.delete()
  end
end

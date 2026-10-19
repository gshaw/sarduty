defmodule App.Operation.DeleteCheckIn do
  @moduledoc """
  Deletes a check-in recorded by mistake (#366), found through the team. The member's
  attendance clock goes back to what it was without it. `:gone` when the team has no such
  check-in, such as one another team admin deleted first.
  """

  alias App.Model.MemberCheckIn
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, check_in_id) do
    case Repo.get_by(MemberCheckIn, id: check_in_id, team_id: team.id) do
      nil -> :gone
      check_in -> {:ok, Repo.delete!(check_in)}
    end
  end
end

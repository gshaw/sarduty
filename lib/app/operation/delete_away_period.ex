defmodule App.Operation.DeleteAwayPeriod do
  @moduledoc """
  Deletes a member's away period (#366), found through the team. The member's history
  keeps its reason and dates. `:gone` when the team has no such period, such as one
  another team admin deleted first.
  """

  alias App.Accounts.User
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberStandingChange
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, period_id, %User{} = user) do
    case MemberAwayPeriod.find(team, period_id) do
      nil -> :gone
      period -> delete(team, period, user)
    end
  end

  defp delete(team, period, user) do
    Repo.transact(fn ->
      Repo.delete!(period)

      MemberStandingChange.insert!(%MemberStandingChange{
        team_id: team.id,
        member_id: period.member_id,
        user_id: user.id,
        action: :away_deleted,
        details: MemberStandingChange.period_details(period)
      })

      {:ok, period}
    end)
  end
end

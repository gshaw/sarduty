defmodule App.Operation.DeleteAwayPeriod do
  @moduledoc """
  Deletes a member's away period (#366), found through the team. The member's history
  keeps its reason and dates.
  """

  alias App.Accounts.User
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberStandingChange
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, period_id, %User{} = user) do
    period = MemberAwayPeriod.find!(team, period_id)

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

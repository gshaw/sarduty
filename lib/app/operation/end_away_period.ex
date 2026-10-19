defmodule App.Operation.EndAwayPeriod do
  @moduledoc """
  Ends a member's current away period early (#366): yesterday becomes its last day, so
  the member is active today. Recorded in the member's history. `:gone` when the team has
  no such period, and `:error` when it isn't current.
  """

  alias App.Accounts.User
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberStandingChange
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, period_id, %User{} = user, now \\ DateTime.utc_now()) do
    with %MemberAwayPeriod{} = period <- MemberAwayPeriod.find(team, period_id) || :gone,
         {:ok, ends_on} <-
           MemberAwayPeriod.early_end(period, Service.Period.today(now, team.timezone)) do
      Repo.transact(fn ->
        ended = period |> Ecto.Changeset.change(ends_on: ends_on) |> Repo.update!()

        MemberStandingChange.insert!(%MemberStandingChange{
          team_id: team.id,
          member_id: period.member_id,
          user_id: user.id,
          action: :away_ended,
          details: MemberStandingChange.period_details(ended)
        })

        {:ok, ended}
      end)
    end
  end
end

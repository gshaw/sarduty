defmodule App.Operation.AddAwayPeriod do
  @moduledoc """
  Adds an away period to a member (#366), found through the team, and records it in the
  member's history. Nothing goes to D4H. A member marked not a person or retired is
  never away, so it returns `:not_a_person` or `:retired` for one.
  """

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberStandingChange
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, member_id, %User{} = user, params, now \\ DateTime.utc_now()) do
    member = Member.find!(team, member_id)

    cond do
      not Member.current?(member, now) -> :retired
      member.not_a_person -> :not_a_person
      true -> add(team, member, user, params)
    end
  end

  defp add(team, member, user, params) do
    changeset =
      MemberAwayPeriod.build_changeset(
        %MemberAwayPeriod{team_id: team.id, member_id: member.id, created_by_user_id: user.id},
        params
      )

    Repo.transact(fn ->
      with {:ok, period} <- Repo.insert(changeset) do
        MemberStandingChange.insert!(%MemberStandingChange{
          team_id: team.id,
          member_id: member.id,
          user_id: user.id,
          action: :away_added,
          details: MemberStandingChange.period_details(period)
        })

        {:ok, period}
      end
    end)
  end
end

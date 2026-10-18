defmodule App.Operation.RecordCheckIn do
  @moduledoc """
  Records that a team admin reached a member (#366), found through the team. It restarts
  the member's attendance clock; nothing else changes, and nothing goes to D4H.
  """

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.MemberCheckIn
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, member_id, %User{} = user, params, now \\ DateTime.utc_now()) do
    member = Member.find!(team, member_id)

    %MemberCheckIn{team_id: team.id, member_id: member.id, user_id: user.id}
    |> MemberCheckIn.build_changeset(params, Service.Period.today(now, team.timezone))
    |> Repo.insert()
  end
end

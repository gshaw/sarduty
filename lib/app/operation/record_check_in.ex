defmodule App.Operation.RecordCheckIn do
  @moduledoc """
  Records that a team admin reached a member (#366), found through the team. It restarts
  the member's attendance clock; nothing else changes, and nothing goes to D4H. A retired
  member or one marked not a person has no clock to restart (#1053), so it returns
  `:retired` or `:not_a_person` for one.
  """

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.MemberCheckIn
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, member_id, %User{} = user, params, now \\ DateTime.utc_now()) do
    member = Member.find!(team, member_id)

    cond do
      not Member.current?(member, now) ->
        :retired

      member.not_a_person ->
        :not_a_person

      true ->
        %MemberCheckIn{team_id: team.id, member_id: member.id, user_id: user.id}
        |> MemberCheckIn.build_changeset(params, Service.Period.today(now, team.timezone))
        |> Repo.insert()
    end
  end
end

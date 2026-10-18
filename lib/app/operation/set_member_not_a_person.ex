defmodule App.Operation.SetMemberNotAPerson do
  @moduledoc """
  Marks a member as not a person, or as a person again. A team admin does this for a bot
  or a shared D4H account, so member counts, home page checks, team admins, and attendance
  at the door leave it out. It lives only in SAR Duty, and the member's history records
  who changed it (#366).
  """

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.MemberStandingChange
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, member_id, %User{} = user, not_a_person)
      when is_boolean(not_a_person) do
    member = Member.find!(team, member_id)

    Repo.transact(fn ->
      updated = member |> Ecto.Changeset.change(not_a_person: not_a_person) |> Repo.update!()

      if member.not_a_person != not_a_person do
        MemberStandingChange.insert!(%MemberStandingChange{
          team_id: team.id,
          member_id: member.id,
          user_id: user.id,
          action: if(not_a_person, do: :not_a_person, else: :person)
        })
      end

      {:ok, updated}
    end)
  end
end

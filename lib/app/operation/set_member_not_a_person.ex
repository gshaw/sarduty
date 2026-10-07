defmodule App.Operation.SetMemberNotAPerson do
  @moduledoc """
  Marks a member as not a person, or as a person again. A team admin does this for a bot
  or a shared D4H account, so member counts, home page checks, team admins, and attendance
  at the door leave it out. It lives only in SAR Duty.
  """

  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, member_id, not_a_person) when is_boolean(not_a_person) do
    team
    |> Member.find!(member_id)
    |> Ecto.Changeset.change(not_a_person: not_a_person)
    |> Repo.update!()
  end
end

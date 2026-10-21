defmodule App.Operation.SaveChore do
  @moduledoc """
  Logging, changing, and deciding chores (#341). A member logs and changes their own
  chores while they wait; a team admin accepts, declines, or changes any of them.
  Nothing here calls D4H.
  """

  import Ecto.Query

  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  @doc "A member logs a chore. `{:ok, chore}` or `{:error, changeset}`."
  def log(%Member{} = member, params, %Date{} = today) do
    %Chore{team_id: member.team_id, member_id: member.id}
    |> Chore.build_changeset(params, category_ids(member.team_id, nil), today)
    |> Repo.insert()
  end

  @doc "A member changes their own chore while it waits."
  def change_own(%Member{} = member, %Chore{} = chore, params, %Date{} = today) do
    true = own?(member, chore) and Chore.member_can_change?(chore)

    chore
    |> Chore.build_changeset(params, category_ids(member.team_id, chore), today)
    |> Repo.update()
  end

  @doc "A member deletes their own chore while it waits, or once declined."
  def delete_own(%Member{} = member, %Chore{} = chore) do
    true = own?(member, chore) and Chore.member_can_delete?(chore)
    {:ok, _chore} = Repo.delete(chore)
    :ok
  end

  @doc "A team admin changes any field of a chore, with any date, in any status."
  def change(%Team{} = team, %Chore{team_id: team_id} = chore, params)
      when team_id == team.id do
    chore
    |> Chore.build_changeset(params, category_ids(team.id, chore), nil)
    |> Repo.update()
  end

  @doc """
  A team admin accepts the team's waiting chores among `ids`. Others are left as they
  are. Returns how many were accepted.
  """
  def accept(%Team{} = team, ids, user, now) do
    {count, _rows} =
      Chore
      |> where([c], c.team_id == ^team.id and c.status == :waiting and c.id in ^ids)
      |> Repo.update_all(
        set: [
          status: :accepted,
          decided_by_user_id: user.id,
          decided_at: now,
          decline_reason: nil,
          updated_at: now
        ]
      )

    count
  end

  @doc "A team admin accepts one chore, in any status."
  def accept_one(%Team{} = team, %Chore{team_id: team_id} = chore, user, now)
      when team_id == team.id do
    chore |> Chore.decide_changeset(:accepted, user, now) |> Repo.update()
  end

  @doc "A team admin declines a chore with a reason the member sees."
  def decline(%Team{} = team, %Chore{team_id: team_id} = chore, reason, user, now)
      when team_id == team.id do
    chore |> Chore.decide_changeset(:declined, user, now, reason) |> Repo.update()
  end

  defp own?(member, chore), do: chore.member_id == member.id and chore.team_id == member.team_id

  # The open categories, and the chore's own even once archived, so saving it again works.
  defp category_ids(team_id, chore) do
    open = team_id |> ChoreCategory.get_open() |> Enum.map(& &1.id)
    if chore, do: Enum.uniq([chore.chore_category_id | open]), else: open
  end
end

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

  @doc """
  A member changes their own chore while it waits. `{:error, :decided}` once a team admin
  has decided it, even after the member's page opened.
  """
  def change_own(%Member{} = member, %Chore{} = chore, params, %Date{} = today) do
    transaction(fn ->
      with {:ok, current} <- own_now(member, chore, &Chore.member_can_change?/1) do
        current
        |> Chore.build_changeset(params, category_ids(member.team_id, current), today)
        |> Repo.update()
      end
    end)
  end

  @doc """
  A member deletes their own chore while it waits, or once declined. `:ok`, or
  `{:error, :decided}` once a team admin has accepted it.
  """
  def delete_own(%Member{} = member, %Chore{} = chore) do
    result =
      transaction(fn ->
        with {:ok, current} <- own_now(member, chore, &Chore.member_can_delete?/1),
             do: Repo.delete(current)
      end)

    with {:ok, _chore} <- result, do: :ok
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

  # The member's chore as it is now, read in the transaction: a team admin may have
  # decided it since the member's page loaded it.
  defp own_now(member, chore, allowed?) do
    current = Repo.get_by(Chore, id: chore.id, team_id: member.team_id, member_id: member.id)
    if current && allowed?.(current), do: {:ok, current}, else: {:error, :decided}
  end

  defp transaction(fun), do: Repo.transaction(fn -> fun.() |> ok_or_rollback() end)

  defp ok_or_rollback({:ok, chore}), do: chore
  defp ok_or_rollback({:error, error}), do: Repo.rollback(error)

  # The open categories, and the chore's own even once archived, so saving it again works.
  defp category_ids(team_id, chore) do
    open = team_id |> ChoreCategory.get_open() |> Enum.map(& &1.id)
    if chore, do: Enum.uniq([chore.chore_category_id | open]), else: open
  end
end

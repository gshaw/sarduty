defmodule App.Operation.SaveChore do
  @moduledoc """
  Logging, changing, and deciding chores (#341). A member logs and changes their own
  chores while they wait; a team admin accepts, declines, or changes any of them.

  Nothing here calls D4H. An accepted chore waits until a team admin sends it
  (App.Operation.SendChores). Once sent, it belongs to that send's `ChoreEvent`, and
  changing or declining it marks the event "Changes to send". A sent chore moved to
  another chore category or year leaves its event and is ready to send again. A chore on
  an event D4H has approved cannot change here: SAR Duty could not send the change.

  A team admin's change reads the chore again in its transaction, since another team
  admin or a send may have changed it since the page loaded it.
  """

  import Ecto.Query

  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
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

  @doc """
  A team admin changes any field of a chore, with any date, in any status.
  `{:error, :locked}` once D4H has approved its event.
  """
  def change(%Team{} = team, %Chore{team_id: team_id} = chore, params)
      when team_id == team.id do
    admin_change(team, chore, &Chore.build_changeset(&1, params, category_ids(team.id, &1), nil))
  end

  @doc """
  A team admin accepts the team's waiting chores among `ids`. Others are left as they
  are. Returns how many were accepted.
  """
  def accept(%Team{} = team, ids, user, now) do
    {:ok, count} =
      Repo.transaction(fn ->
        chores =
          Chore
          |> where([c], c.team_id == ^team.id and c.status == :waiting and c.id in ^ids)
          |> Repo.all()

        Enum.each(chores, fn chore ->
          {:ok, _chore} = chore |> Chore.decide_changeset(:accepted, user, now) |> decide(chore)
        end)

        length(chores)
      end)

    count
  end

  @doc "A team admin accepts one chore, in any status. `{:error, :locked}` as `change/3`."
  def accept_one(%Team{} = team, %Chore{team_id: team_id} = chore, user, now)
      when team_id == team.id,
      do: admin_change(team, chore, &Chore.decide_changeset(&1, :accepted, user, now))

  @doc "A team admin declines a chore with a reason the member sees. `{:error, :locked}` as `change/3`."
  def decline(%Team{} = team, %Chore{team_id: team_id} = chore, reason, user, now)
      when team_id == team.id,
      do: admin_change(team, chore, &Chore.decide_changeset(&1, :declined, user, now, reason))

  defp admin_change(team, chore, build) do
    transaction(fn ->
      current = Repo.get_by!(Chore, id: chore.id, team_id: team.id)

      if Chore.locked?(current),
        do: {:error, :locked},
        else: current |> build.() |> decide(current)
    end)
  end

  # The member's chore as it is now, read in the transaction: a team admin may have
  # decided it since the member's page loaded it.
  defp own_now(member, chore, allowed?) do
    current = Repo.get_by(Chore, id: chore.id, team_id: member.team_id, member_id: member.id)
    if current && allowed?.(current), do: {:ok, current}, else: {:error, :decided}
  end

  defp decide(changeset, before), do: changeset |> Repo.update() |> place(before)

  # A sent chore stays on its event while it is accepted and still fits it: the same
  # chore category and year. Either way, the event has changes to send.
  defp place({:ok, chore}, %Chore{chore_event_id: nil}), do: {:ok, chore}

  defp place({:ok, chore}, %Chore{chore_event_id: event_id}) do
    event = Repo.get!(ChoreEvent, event_id)
    :ok = ChoreEvent.mark_for_send!([event_id])

    if ChoreEvent.fits?(event, chore),
      do: {:ok, chore},
      else: chore |> Ecto.Changeset.change(chore_event_id: nil) |> Repo.update()
  end

  defp place(error, _before), do: error

  defp transaction(fun), do: Repo.transaction(fn -> fun.() |> ok_or_rollback() end)

  defp ok_or_rollback({:ok, chore}), do: chore
  defp ok_or_rollback({:error, error}), do: Repo.rollback(error)

  # The open categories, and the chore's own even once archived, so saving it again works.
  defp category_ids(team_id, chore) do
    open = team_id |> ChoreCategory.get_open() |> Enum.map(& &1.id)
    if chore, do: Enum.uniq([chore.chore_category_id | open]), else: open
  end
end

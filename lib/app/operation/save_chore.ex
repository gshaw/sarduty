defmodule App.Operation.SaveChore do
  @moduledoc """
  Logging, changing, and deciding chores (#341). A member logs and changes their own
  chores while they wait; a team admin accepts, declines, or changes any of them.

  Nothing here calls D4H. A team admin's decision or change marks the chore's event as
  having changes to send, then puts the team's accepted chores on the events for their
  chore categories and months (`ChoreEvent.place!/1`). The page then sends them
  (App.Operation.SendChores), once for however many chores it decided.

  A team admin's change reads the chore again in its transaction, since another team
  admin or a send may have changed it since the page loaded it.
  """

  import Ecto.Query

  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
  alias App.Model.Member
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Repo

  @doc """
  `logger`, a member of `team`, logs a chore for `people` (#1102): each gets their own
  waiting chore, the same in every other way, logged by `logger`, and sharing a
  `logged_together_id` when there are several. `who` is `:member` or `:team_admin`, from
  who is logged in, and decides the date rule and who may be listed (`check_people/4`).
  Nobody is told, and nothing goes to D4H.

  `{:ok, chores}`, `{:error, changeset}`, or `{:error, reason}` from check_people/4.
  """
  def log(%Team{} = team, %Member{} = logger, people, params, %Date{} = today, who)
      when who in [:member, :team_admin] do
    changeset =
      Chore.build_changeset(%Chore{}, params, category_ids(team.id, nil), today, who)

    transaction(fn ->
      with {:ok, current} <- current_people(team, people),
           {:ok, people} <- check_people(logger, current, who, context_now(team)),
           {:ok, _valid} <- Ecto.Changeset.apply_action(changeset, :insert),
           do: {:ok, insert_all(changeset, people, team, logger)}
    end)
  end

  # The people as they are now: the form's list is from when it opened, and someone on
  # it may have left, retired, or been removed since.
  defp current_people(team, people) do
    ids = people |> Enum.map(& &1.id) |> Enum.uniq()
    found = Member |> where([m], m.team_id == ^team.id and m.id in ^ids) |> Repo.all()
    if length(found) == length(ids), do: {:ok, found}, else: {:error, :not_listed}
  end

  # The team as it is now too: a group may have become its Retiring group.
  defp context_now(team) do
    retiring = Team |> Repo.get!(team.id) |> Standing.retiring_ids()
    %{retiring: retiring, now: DateTime.utc_now()}
  end

  defp insert_all(changeset, people, team, logger) do
    together = if length(people) > 1, do: Ecto.UUID.generate()
    fields = [team_id: team.id, logged_by_member_id: logger.id, logged_together_id: together]
    Enum.map(people, &insert_for(changeset, &1, fields))
  end

  defp insert_for(changeset, person, fields) do
    changeset
    |> Ecto.Changeset.change([{:member_id, person.id} | fields])
    |> Repo.insert!()
  end

  @doc """
  Who `logger` may log a chore for (#1102), with anyone listed twice once: `{:ok, people}`.
  Each is on the logger's team, and anyone but the logger is a current member the team
  counts, so not retiring and not a member who is not a person. The logger may log for
  themselves whatever they are. A member lists themselves; only a team admin may log for
  others alone. `{:error, :nobody}`, `{:error, :without_you}`, or `{:error, :not_listed}`.
  `context` has `retiring`, the team's retiring member ids, and `now`.
  """
  def check_people(%Member{} = logger, people, who, %{retiring: retiring, now: now}) do
    people = Enum.uniq_by(people, & &1.id)

    listable? = fn person ->
      person.team_id == logger.team_id and
        (person.id == logger.id or
           (Member.current?(person, now) and Member.counted?(person, retiring)))
    end

    cond do
      people == [] -> {:error, :nobody}
      who == :member and not Enum.any?(people, &(&1.id == logger.id)) -> {:error, :without_you}
      not Enum.all?(people, listable?) -> {:error, :not_listed}
      true -> {:ok, people}
    end
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
  `{:error, :decided}` once a team admin has accepted it. A team admin, `who`
  `:team_admin`, deletes only a declined one, and `{:error, :others_wait}` while a chore
  logged with it waits (`Chore.team_admin_can_delete?/1`): deleting it would end Accept my
  own chores for the rest.
  """
  def delete_own(%Member{} = member, %Chore{} = chore, who \\ :member) do
    allowed? =
      if who == :team_admin,
        do: &(&1.status == :declined),
        else: &Chore.member_can_delete?/1

    result =
      transaction(fn ->
        with {:ok, current} <- own_now(member, chore, allowed?),
             :ok <- others_wait(current, who),
             do: Repo.delete(current)
      end)

    with {:ok, _chore} <- result, do: :ok
  end

  @doc "A team admin changes any field of a chore, with any date that has passed, in any status."
  def change(%Team{} = team, %Chore{team_id: team_id} = chore, params, %Date{} = today)
      when team_id == team.id do
    admin_change(
      team,
      chore,
      &Chore.build_changeset(&1, params, category_ids(team.id, &1), today, :team_admin)
    )
  end

  @doc """
  A team admin accepts the team's waiting chores among `ids`, and every waiting chore
  logged together with one of them (#1102), whatever that one's status is now: Waiting
  sends one id for a row. Others are left as they are. `{:ok, count}`, or `{:error,
  :own}` when they include the team admin's own and `own: true` doesn't say they meant it
  (#697).

  `member:` is the team admin's member on the team, or nil.
  """
  def accept(%Team{} = team, ids, user, now, opts) do
    member = Keyword.fetch!(opts, :member)

    together =
      from c in Chore,
        where: c.team_id == ^team.id and c.id in ^ids and not is_nil(c.logged_together_id),
        select: c.logged_together_id

    Repo.transaction(fn ->
      chores =
        Chore
        |> where([c], c.team_id == ^team.id and c.status == :waiting)
        |> where([c], c.id in ^ids or c.logged_together_id in subquery(together))
        |> preload(logged_with: ^Chore.logged_with_query(team.id))
        |> Repo.all()

      if own_unmeant?(chores, member, opts), do: Repo.rollback(:own)

      Enum.each(chores, fn chore ->
        {:ok, _chore} = chore |> Chore.decide_changeset(:accepted, user, now) |> Repo.update()
      end)

      :ok = ChoreEvent.place!(team.id)
      length(chores)
    end)
  end

  @doc """
  A team admin accepts one chore, in any status. `{:error, :own}` for their own unless
  `own: true`, as accept/5.
  """
  def accept_one(%Team{} = team, %Chore{team_id: team_id} = chore, user, now, opts)
      when team_id == team.id do
    member = Keyword.fetch!(opts, :member)

    admin_change(
      team,
      chore,
      &Chore.decide_changeset(&1, :accepted, user, now),
      &if(own_unmeant?([&1], member, opts), do: {:error, :own}, else: :ok)
    )
  end

  @doc """
  Whether `chores` include `member`'s own and `opts` lack `own: true`. Another team admin
  should accept a team admin's chores, but they may accept their own when they say so.
  """
  def own_unmeant?(chores, member, opts),
    do: Keyword.get(opts, :own) != true and Enum.any?(chores, &Chore.own?(&1, member))

  @doc "A team admin declines a chore with a reason the member sees."
  def decline(%Team{} = team, %Chore{team_id: team_id} = chore, reason, user, now)
      when team_id == team.id,
      do: admin_change(team, chore, &Chore.decide_changeset(&1, :declined, user, now, reason))

  # The chore's event has changes to send even when the chore stays on it, since its
  # minutes or what it says may have changed. Placing it may move it to another event.
  defp admin_change(team, chore, build, check \\ fn _chore -> :ok end) do
    transaction(fn ->
      current =
        Chore
        |> Repo.get_by!(id: chore.id, team_id: team.id)
        |> Repo.preload(logged_with: Chore.logged_with_query(team.id))

      with :ok <- check.(current),
           {:ok, saved} <- current |> build.() |> Repo.update() do
        :ok = ChoreEvent.mark_for_send!([current.chore_event_id])
        :ok = ChoreEvent.place!(team.id)
        {:ok, Repo.get!(Chore, saved.id)}
      end
    end)
  end

  # The member's chore as it is now, read in the transaction: a team admin may have
  # decided it since the member's page loaded it.
  defp own_now(member, chore, allowed?) do
    current =
      Chore
      |> Repo.get_by(id: chore.id, team_id: member.team_id, member_id: member.id)
      |> Repo.preload(logged_with: Chore.logged_with_query(member.team_id))

    if current && allowed?.(current), do: {:ok, current}, else: {:error, :decided}
  end

  defp others_wait(chore, :team_admin),
    do: if(Chore.team_admin_can_delete?(chore), do: :ok, else: {:error, :others_wait})

  defp others_wait(_chore, :member), do: :ok

  defp transaction(fun), do: Repo.transaction(fn -> fun.() |> ok_or_rollback() end)

  defp ok_or_rollback({:ok, chore}), do: chore
  defp ok_or_rollback({:error, error}), do: Repo.rollback(error)

  # The open categories, and the chore's own even once archived, so saving it again works.
  defp category_ids(team_id, chore) do
    open = team_id |> ChoreCategory.get_open() |> Enum.map(& &1.id)
    if chore, do: Enum.uniq([chore.chore_category_id | open]), else: open
  end
end

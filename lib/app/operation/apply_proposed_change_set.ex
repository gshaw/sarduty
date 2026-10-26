defmodule App.Operation.ApplyProposedChangeSet do
  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.SendChores
  alias App.Repo

  # A team admin applies an agent's change set (#216), with the rows they ticked. The
  # rows they didn't tick are skipped, so the set records what the person decided.

  @doc """
  Applies the ticked rows of a waiting set. Row ids the browser sent that aren't in the
  set are ignored. Returns what `ApplyChangeSet.call/4` returns, or `{:error, :decided}`
  for a set already applied or discarded, or `{:error, :none_selected}`.
  """
  def call(%Team{} = team, %ChangeSet{} = change_set, %User{} = user, selected_row_ids, now) do
    selected = MapSet.new(selected_row_ids)
    {ticked, unticked} = Enum.split_with(change_set.rows, &MapSet.member?(selected, &1.id))

    cond do
      not ChangeSet.waiting?(change_set) -> {:error, :decided}
      ticked == [] -> {:error, :none_selected}
      true -> apply_ticked(team, change_set, user, unticked, now)
    end
  end

  # When D4H refuses the whole set, such as a published activity, nothing was decided,
  # so the unticked rows go back to waiting.
  defp apply_ticked(team, change_set, user, unticked, now) do
    skipped = Enum.map(unticked, &ChangeSetRow.record!(&1, {:skipped, "Not selected"}, now))
    change_set = Repo.preload(change_set, :rows, force: true)

    case ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, rows} ->
        drop_removed_rows(team, rows)
        copy_tags(team, rows)
        {:ok, rows ++ add_chores(team, change_set, user, now)}

      {:error, _reason} = error ->
        Enum.each(skipped, &ChangeSetRow.reset!/1)
        error
    end
  end

  # The ticked chores an agent proposed (#595) become chores, accepted by this team admin,
  # then go to D4H like any accepted chore. ApplyChangeSet leaves these rows alone: they
  # are SAR Duty's own.
  defp add_chores(team, change_set, user, now) do
    rows =
      for row <- Repo.preload(change_set, :rows, force: true).rows,
          row.action == :add_chore and row.status == :proposed,
          do: row

    if rows == [] do
      []
    else
      today = Service.Period.today(now, team.timezone)
      open = team.id |> ChoreCategory.get_open() |> Enum.map(& &1.id)

      {:ok, recorded} =
        Repo.transaction(fn ->
          recorded = Enum.map(rows, &add_chore(team, &1, {open, today}, user, now))
          :ok = ChoreEvent.place!(team.id)
          recorded
        end)

      if Enum.any?(recorded, &(&1.status == :applied)), do: SendChores.call(team, user, now)
      recorded
    end
  end

  defp add_chore(team, row, {open, today}, user, now) do
    params = Map.take(row.new_value, ~w(date minutes chore_category_id description))

    inserted =
      %Chore{team_id: team.id, member_id: row.member_id, change_set_row_id: row.id}
      |> Chore.build_changeset(params, open, today, :team_admin)
      |> Ecto.Changeset.change(status: :accepted, decided_by_user_id: user.id, decided_at: now)
      |> Repo.insert()

    case inserted do
      {:ok, _chore} -> ChangeSetRow.record!(row, {:applied, nil}, now)
      {:error, changeset} -> ChangeSetRow.record!(row, {:skipped, first_error(changeset)}, now)
    end
  end

  defp first_error(changeset) do
    {_field, {message, _opts}} = hd(changeset.errors)
    "#{message}. Propose it again."
  end

  # An activity's new tags show before the next refresh, as on its Change tags page. A
  # tag the copy has no title for yet waits for the refresh.
  defp copy_tags(team, rows) do
    titles = team.id |> Tag.get_all() |> Map.new(&{&1.d4h_tag_id, &1.title})

    for %{action: :set_activity_tags, status: :applied} = row <- rows,
        activity = Repo.get_by(Activity, team_id: team.id, d4h_activity_id: row.d4h_record_id) do
      tags = row.new_value["tag_ids"] |> Enum.flat_map(&List.wrap(titles[&1])) |> Enum.sort()
      activity |> Ecto.Changeset.change(tags: tags) |> Repo.update!()
    end
  end

  # A row D4H took off leaves the copy now. The sync finds deletes on an activity nothing
  # else touched only one month per round (docs/d4h-sync.md), and until then the row
  # would still count.
  defp drop_removed_rows(team, rows) do
    ids = for %{action: :delete_attendance, status: :applied} = row <- rows, do: row.d4h_record_id

    team_activities = from(ac in Activity, where: ac.team_id == ^team.id, select: ac.id)

    Attendance
    |> where([a], a.activity_id in subquery(team_activities) and a.d4h_attendance_id in ^ids)
    |> Repo.delete_all()
  end
end

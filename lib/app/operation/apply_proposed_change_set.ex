defmodule App.Operation.ApplyProposedChangeSet do
  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
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

    # Making a published activity a draft and publishing it again go with any change
    # (#595); a team admin never ticks them.
    {ticked, unticked} =
      Enum.split_with(
        change_set.rows,
        &(MapSet.member?(selected, &1.id) or &1.action == :publish_activity)
      )

    cond do
      not ChangeSet.waiting?(change_set) -> {:error, :decided}
      Enum.all?(ticked, &(&1.action == :publish_activity)) -> {:error, :none_selected}
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
        {:ok, rows}

      {:error, _reason} = error ->
        Enum.each(skipped, &ChangeSetRow.reset!/1)
        error
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

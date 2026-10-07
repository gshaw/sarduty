defmodule App.Operation.ApplyProposedChangeSet do
  alias App.Accounts.User
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

    with {:error, _reason} = error <- ApplyChangeSet.call(team, change_set, user, now) do
      Enum.each(skipped, &ChangeSetRow.reset!/1)
      error
    end
  end
end

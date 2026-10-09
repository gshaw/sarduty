defmodule App.Operation.ApplyEdit do
  @moduledoc """
  One change a team admin makes to a record of a team on SAR Duty Records
  (docs/records.md): a change set of one row, source `:edit`, applied at once like the
  door's. Then the sync copies what changed, so the page that follows shows it.

  `{:ok, d4h_record_id}`, or `{:error, text}` to show the person.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.SyncD4HChanges

  require Logger

  def call(team, user, row, now, opts \\ [])

  # D4H has no such writes, and its teams change records in D4H.
  def call(%Team{} = team, %User{} = user, %ChangeSetRow{} = row, now, opts) do
    if D4H.records?(team),
      do: apply_row(team, user, row, now, opts),
      else: {:error, "Change this in D4H."}
  end

  defp apply_row(team, user, row, now, opts) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :edit,
          activity_id: opts[:activity_id],
          group_id: opts[:group_id],
          proposed_by_user_id: user.id
        },
        [row]
      )

    case ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, [%ChangeSetRow{status: :applied} = applied]} ->
        sync(team)
        {:ok, applied.d4h_record_id}

      {:ok, [%ChangeSetRow{error: error}]} ->
        {:error, error}

      {:error, reason} ->
        {:error, describe(reason)}
    end
  end

  # The edit is saved either way; a failed sync leaves the copy for the next one.
  defp sync(team) do
    case team.id |> Team.get!() |> SyncD4HChanges.call() do
      {:ok, _team, _changed} -> :ok
      error -> Logger.warning("Sync after an edit failed for team #{team.id}: #{inspect(error)}")
    end
  rescue
    error ->
      Logger.warning("Sync after an edit failed for team #{team.id}: #{inspect(error)}")
  end

  defp describe(:no_team_key), do: "This team has no key. Ask a SAR Duty admin."
  defp describe(:deleted), do: "This activity is deleted. Nothing can change on it."
  defp describe(:published), do: "This activity is published. Unpublish it first."
  defp describe(error) when is_exception(error), do: Exception.message(error)
end

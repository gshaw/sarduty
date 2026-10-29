defmodule App.Operation.ApplyEdit do
  @moduledoc """
  One change a team admin makes to a record: a change set of one row, source `:edit`,
  applied at once like the door's. A team on SAR Duty Records changes any record this way
  (docs/records.md). A D4H team changes its groups and who is in them (#546), and adds and
  changes activities (#585) and the custom fields of members and equipment items (#705);
  every other record it changes in D4H.

  After a group row the caller writes the local copy, as group rules do, and the next
  sync confirms it. After any other row the sync copies what changed, so the page that
  follows shows it.

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

  # D4H takes these writes too (tested on South Fraser, 2026-10-24). A sync after each
  # would fetch every group's members, seconds per click, and overlap the 10-minute sync.
  @group_actions [
    :create_group,
    :update_group,
    :delete_group,
    :add_group_member,
    :remove_group_member
  ]

  def call(team, user, row, now, opts \\ [])

  # D4H cannot delete an activity.
  @activity_actions [:create_activity, :update_activity]

  def call(%Team{} = team, %User{} = user, %ChangeSetRow{} = row, now, opts) do
    if D4H.records?(team) or row.action in @group_actions or row.action in @activity_actions or
         custom_fields_only?(row),
       do: apply_row(team, user, row, now, opts),
       else: {:error, "Change this in #{D4H.service_name(team)}."}
  end

  # A member's or item's custom fields, from its Change fields page (#705). D4H's PATCH
  # takes them; its other fields change in D4H.
  defp custom_fields_only?(%ChangeSetRow{action: action, new_value: new_value}),
    do:
      action in [:update_member, :update_equipment_item] and
        Map.keys(new_value) == ["custom_values"]

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

    case ApplyChangeSet.call(team, change_set, user, now, Keyword.take(opts, [:photo, :document])) do
      {:ok, [%ChangeSetRow{status: :applied} = applied]} ->
        if applied.action not in @group_actions, do: sync(team)
        {:ok, applied.d4h_record_id}

      {:ok, [%ChangeSetRow{error: error}]} ->
        {:error, error}

      {:error, reason} ->
        {:error, describe(team, reason)}
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

  defp describe(_team, :no_team_key), do: "This team has no key. Ask a SAR Duty admin."
  defp describe(_team, :deleted), do: "This activity is deleted. Nothing can change on it."
  defp describe(_team, :published), do: "This activity is published. Unpublish it first."
  defp describe(team, error) when is_exception(error), do: D4H.error_text(team, error)
end

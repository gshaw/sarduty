defmodule App.Operation.ApplyEdit do
  @moduledoc """
  One change a team admin makes to a record: a change set of one row, source `:edit`,
  applied at once like the door's. A team on SAR Duty Records changes any record this way
  (docs/records.md). A D4H team changes its groups and who is in them (#546), adds and
  changes activities (#585), changes members' details and custom fields (#705), sets and
  removes members' photos (#1028) and the team's logo (#1075), retires and rejoins members
  (#1053), changes equipment items' status, barcode, and custom fields, and adds and
  changes its own fields and their bundles (#1056); every other record it changes in D4H.

  After a group row, a retire, or a rejoin the caller writes the local copy, as group
  rules do, and the next sync confirms it. After any other row the sync copies what
  changed, so the page that follows shows it.

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

  # A team's own fields, their choices, and bundles (#1056). The caller updates the copy
  # from D4H's answer on each row.
  @field_actions [
    :create_custom_field,
    :update_custom_field,
    :delete_custom_field,
    :create_custom_field_option,
    :update_custom_field_option,
    :create_resource_bundle
  ]

  # The caller writes these rows' local copy, and the next sync confirms it: a sync after
  # a retire took about 10 seconds on South Fraser (#1053).
  # A team logo's copy is saved by SetTeamLogo, and the sync never reads logos (#1075).
  @local_copy_actions @group_actions ++
                        @field_actions ++
                        [:retire_member, :rejoin_member, :set_team_logo, :remove_team_logo]

  def call(team, user, row, now, opts \\ [])

  # D4H cannot delete an activity.
  @activity_actions [:create_activity, :update_activity]

  def call(%Team{} = team, %User{} = user, %ChangeSetRow{} = row, now, opts) do
    if D4H.records?(team) or row.action in @group_actions or row.action in @activity_actions or
         d4h_takes?(row),
       do: apply_row(team, user, row, now, opts),
       else: {:error, "Change this in #{D4H.service_name(team)}."}
  end

  # What D4H's PATCH takes from a member's Change member and Change fields pages. Access
  # (`permission`) is not among them: D4H sets it only in its web app.
  @d4h_member_keys ~w(name ref_id position email phone address status joined_at custom_values)

  # What D4H's equipment PATCH takes: an item's name, place, serial, and expiry change
  # only in its web app.
  @d4h_item_keys ~w(status barcode custom_values)

  @doc """
  Whether a D4H team may send `row`: a member or item row with only the fields D4H's
  PATCH takes.
  """
  def d4h_takes?(%ChangeSetRow{action: :update_member, new_value: new_value}),
    do: only?(new_value, @d4h_member_keys)

  def d4h_takes?(%ChangeSetRow{action: :update_equipment_item, new_value: new_value}),
    do: only?(new_value, @d4h_item_keys)

  # A member's photo or the team's logo, as a document D4H makes the profile image
  # (#1028, #1075), and retiring or rejoining a member (#1053).
  @d4h_actions [
    :set_member_photo,
    :remove_member_photo,
    :set_team_logo,
    :remove_team_logo,
    :retire_member,
    :rejoin_member
  ]
  def d4h_takes?(%ChangeSetRow{action: action}) when action in @d4h_actions, do: true

  def d4h_takes?(%ChangeSetRow{action: action}) when action in @field_actions, do: true

  def d4h_takes?(%ChangeSetRow{}), do: false

  defp only?(new_value, keys),
    do: new_value != %{} and new_value |> Map.keys() |> Enum.all?(&(&1 in keys))

  @doc """
  One change made of several rows, sent in order as one set: a field and the bundle it
  goes in, or a team's fields in a new order (#1056). Only rows whose caller writes the
  local copy, so no sync follows. `{:ok, rows}` with each row as recorded, D4H's answer
  in `answer` on an applied one; or `{:error, text}` when nothing was sent.
  """
  def call_rows(%Team{} = team, %User{} = user, [_ | _] = rows, now) do
    unless Enum.all?(rows, &(&1.action in @local_copy_actions)),
      do: raise(ArgumentError, "call_rows/4 takes only rows whose caller writes the copy")

    if D4H.records?(team) or Enum.all?(rows, &d4h_takes?/1),
      do: team |> send_set(user, rows, now, []) |> described(team),
      else: {:error, "Change this in #{D4H.service_name(team)}."}
  end

  defp described({:ok, rows}, _team), do: {:ok, rows}
  defp described({:error, reason}, team), do: {:error, describe(team, reason)}

  defp apply_row(team, user, row, now, opts) do
    case send_set(team, user, [row], now, opts) do
      {:ok, [%ChangeSetRow{status: :applied} = applied]} ->
        if applied.action not in @local_copy_actions, do: sync(team)
        {:ok, applied.d4h_record_id}

      {:ok, [%ChangeSetRow{error: error}]} ->
        {:error, error}

      {:error, reason} ->
        {:error, describe(team, reason)}
    end
  end

  defp send_set(team, user, rows, now, opts) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :edit,
          activity_id: opts[:activity_id],
          group_id: opts[:group_id],
          proposed_by_user_id: user.id
        },
        rows
      )

    ApplyChangeSet.call(
      team,
      change_set,
      user,
      now,
      Keyword.take(opts, [:photo, :logo, :document])
    )
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

  defp describe(_team, :no_team_key), do: "This team has no key. Ask a SAR Duty site admin."
  defp describe(_team, :deleted), do: "This activity is deleted. Nothing can change on it."
  defp describe(_team, :published), do: "This activity is published. Unpublish it first."
  defp describe(team, error) when is_exception(error), do: D4H.error_text(team, error)
end

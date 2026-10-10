defmodule App.Operation.ChangeActivityEquipment do
  @moduledoc """
  Adds equipment to an activity, or removes one item, in D4H (#271). Each is a change
  set of source `:equipment`, applied at once, with one row per item. Then the
  activity's usages are read back from D4H, so its page shows them before the next sync.

  plan_adds/2 decides which items to add; add/5 and remove/5 write.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.RefreshD4HData.UpsertEquipmentUsages

  require Logger

  @doc """
  The rows that add `lines` to an activity. A line is `%{item: %EquipmentItem{},
  minutes: n}`. An item already on the activity (`used_d4h_ids`), or on an earlier line,
  is left out. Minutes go only with equipment; D4H takes km for a vehicle and a count
  for a supply.
  """
  def plan_adds(%Activity{} = activity, lines, used_d4h_ids \\ []) do
    lines
    |> Enum.uniq_by(& &1.item.d4h_equipment_id)
    |> Enum.reject(&(&1.item.d4h_equipment_id in used_d4h_ids))
    |> Enum.map(fn %{item: item, minutes: minutes} ->
      %ChangeSetRow{
        action: :create_equipment_usage,
        new_value: %{
          "d4h_activity_id" => activity.d4h_activity_id,
          "d4h_equipment_id" => item.d4h_equipment_id,
          "title" => item.title,
          "minutes" => if(EquipmentItem.takes_hours?(item), do: max(minutes || 0, 0))
        }
      }
    end)
  end

  @doc "Adds `lines` to the activity. `{:ok, rows}`, or `{:error, text}` to show."
  def add(%Team{} = team, %Activity{} = activity, lines, %User{} = user, now) do
    used =
      activity |> EquipmentUsage.for_activity() |> Enum.map(& &1.equipment_item.d4h_equipment_id)

    case plan_adds(activity, lines, used) do
      [] -> {:error, "Every item is on the activity already."}
      rows -> apply_rows(team, activity, rows, user, now)
    end
  end

  @doc "Removes one usage from the activity. `{:ok, rows}`, or `{:error, text}` to show."
  def remove(%Team{} = team, %Activity{} = activity, %EquipmentUsage{} = usage, user, now)
      when usage.activity_id == activity.id do
    row = %ChangeSetRow{
      action: :delete_equipment_usage,
      d4h_record_id: usage.d4h_equipment_usage_id,
      old_value: %{
        "d4h_equipment_id" => usage.equipment_item.d4h_equipment_id,
        "title" => usage.equipment_item.title,
        "minutes" => usage.minutes
      }
    }

    apply_rows(team, activity, [row], user, now)
  end

  defp apply_rows(team, activity, rows, user, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :equipment,
          activity_id: activity.id,
          proposed_by_user_id: user.id
        },
        rows
      )

    case ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, rows} ->
        read_back(team, activity)
        {:ok, rows}

      {:error, reason} ->
        {:error, describe(team, reason)}
    end
  end

  # The change is in D4H either way; a failed read leaves the copy for the next sync.
  defp read_back(team, activity) do
    d4h = D4H.build_context_from_team(team)

    case D4H.fetch_activity_equipment_usages(d4h, activity.d4h_activity_id) do
      {:ok, usages} -> UpsertEquipmentUsages.replace_for_activity(activity, usages)
      {:error, error} -> Logger.warning("Equipment read back failed: #{Exception.message(error)}")
    end
  end

  defp describe(_team, :no_team_key), do: "Save a D4H access key in team settings first."
  defp describe(_team, :deleted), do: "This activity is deleted in D4H."

  defp describe(_team, %D4H.Error{} = error),
    do: "D4H did not answer. #{Exception.message(error)}"
end

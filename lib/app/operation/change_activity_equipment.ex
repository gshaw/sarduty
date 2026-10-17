defmodule App.Operation.ChangeActivityEquipment do
  @moduledoc """
  Adds equipment and a template's tags to an activity, or removes one item, in D4H (#271,
  #162). Each is a change set of source `:equipment`, applied at once, with one row per
  item and one for the tags. Then the activity's usages are read back from D4H, and its
  added tags copied, so its page shows them before the next sync.

  plan_adds/3 decides which items to add and plan_tags/3 which tags; add/6 and remove/5
  write.
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
  alias App.Repo

  require Logger

  @doc """
  The rows that add `lines` to an activity. A line is `%{item: %EquipmentItem{},
  minutes: n}`, with `km: n` for a vehicle. An item already on the activity
  (`used_d4h_ids`), or on an earlier line, is left out. Minutes go only with equipment
  and km only with a vehicle, as D4H takes them. A supply's count is left out.
  """
  def plan_adds(%Activity{} = activity, lines, used_d4h_ids \\ []) do
    lines
    |> Enum.uniq_by(& &1.item.d4h_equipment_id)
    |> Enum.reject(&(&1.item.d4h_equipment_id in used_d4h_ids))
    |> Enum.map(fn %{item: item, minutes: minutes} = line ->
      %ChangeSetRow{
        action: :create_equipment_usage,
        new_value: %{
          "d4h_activity_id" => activity.d4h_activity_id,
          "d4h_equipment_id" => item.d4h_equipment_id,
          "title" => item.title,
          "minutes" => if(EquipmentItem.takes_hours?(item), do: max(minutes || 0, 0)),
          "km" => if(EquipmentItem.takes_km?(item), do: line[:km])
        }
      }
    end)
  end

  @doc """
  The row that adds `tags` to an activity whose tags are `current_tag_ids` now, or nil when
  it has them all. D4H replaces an activity's whole tag list, so the row sends the
  current tags and the new ones together, each id once.
  """
  def plan_tags(%Activity{} = activity, current_tag_ids, tags) do
    current_tag_ids = Enum.uniq(current_tag_ids)

    new =
      tags
      |> Enum.uniq_by(& &1.d4h_tag_id)
      |> Enum.reject(&(&1.d4h_tag_id in current_tag_ids))

    if new != [] do
      %ChangeSetRow{
        action: :set_activity_tags,
        d4h_record_id: activity.d4h_activity_id,
        old_value: %{"kind" => activity.activity_kind, "tag_ids" => Enum.sort(current_tag_ids)},
        new_value: %{
          "tag_ids" => Enum.sort(current_tag_ids ++ Enum.map(new, & &1.d4h_tag_id)),
          "titles" => Enum.map(new, & &1.title)
        }
      }
    end
  end

  @doc """
  Adds `lines` and `tags` (`%Tag{}`s) to the activity. `{:ok, rows}`, or `{:error, text}`
  to show.
  """
  def add(%Team{} = team, %Activity{} = activity, lines, tags, %User{} = user, now) do
    used =
      activity |> EquipmentUsage.for_activity() |> Enum.map(& &1.equipment_item.d4h_equipment_id)

    with {:ok, tag_row} <- plan_tag_row(team, activity, tags) do
      case plan_adds(activity, lines, used) ++ List.wrap(tag_row) do
        [] when tags == [] -> {:error, "Every item is on the activity already."}
        [] -> {:error, "Every item and tag is on the activity already."}
        rows -> apply_rows(team, activity, rows, user, now)
      end
    end
  end

  # Tags are read from D4H now: a list from the last sync could drop a tag added since.
  defp plan_tag_row(_team, _activity, []), do: {:ok, nil}

  defp plan_tag_row(%Team{d4h_access_key: nil} = team, _activity, _tags),
    do: {:error, describe(team, :no_team_key)}

  defp plan_tag_row(team, activity, tags) do
    d4h = D4H.build_context_from_team(team)

    case D4H.fetch_activity_tag_ids(d4h, activity.d4h_activity_id, activity.activity_kind) do
      {:ok, current} -> {:ok, plan_tags(activity, current, tags)}
      {:error, error} -> {:error, describe(team, error)}
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
        copy_tags(activity, rows)
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

  defp copy_tags(activity, rows) do
    case Enum.find(rows, &(&1.action == :set_activity_tags and &1.status == :applied)) do
      nil ->
        :ok

      row ->
        tags =
          ((activity.tags || []) ++ row.new_value["titles"])
          |> Enum.uniq()
          |> Activity.sort_tags()

        activity |> Ecto.Changeset.change(tags: tags) |> Repo.update!()
    end
  end

  defp describe(team, :no_team_key), do: "Save a #{D4H.key_name(team)} in team settings first."
  defp describe(team, :deleted), do: "This activity is deleted in #{D4H.service_name(team)}."

  defp describe(team, %D4H.Error{} = error),
    do: "#{D4H.service_name(team)} did not answer. #{Exception.message(error)}"
end

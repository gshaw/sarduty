defmodule App.Operation.SaveCustomFields do
  @moduledoc """
  A team admin changes a record's D4H custom fields on its Change fields page (#705): an
  activity's, a member's copied ones, or an equipment item's. plan/3 turns the form into
  one change set row naming only the fields that changed; call/5 applies it through
  App.Operation.ApplyEdit, then writes what it sent to the copy, since D4H doesn't change
  a record's updatedAt for its custom fields and the sync may not read them back (#681).

  A published activity is locked, as for its other details. Apply a template (#307) sends
  its values through call/5 too, after fill_empty/4 picks the ones that go.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.ChangeSetRow
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyEdit

  @doc """
  The fields `record`'s Change fields page offers, in D4H's order: its kind's for an
  activity, the ones the team copies for a member, and every one for an item.
  """
  def fields(%Team{} = team, %Activity{activity_kind: kind}),
    do: CustomField.get_all(team.id, kind)

  def fields(%Team{} = team, %Member{}),
    do: CustomField.copied_member_fields(team.id, :team_admin)

  def fields(%Team{} = team, %EquipmentItem{}), do: CustomField.get_all(team.id, "equipment")

  @doc """
  `{:ok, record}` with the values sent, or `{:error, text}` when the activity is
  published or D4H refused. `params` are the form's values by D4H field id.
  """
  def call(%Team{} = team, record, params, %User{} = user, now) when is_map(params) do
    if locked?(record) do
      {:error, "A published activity cannot be changed. #{D4H.unpublish_text(team)}"}
    else
      case plan(record, fields(team, record), params) do
        :unchanged -> {:ok, record}
        row -> apply_row(team, user, record, row, now)
      end
    end
  end

  defp locked?(%Activity{} = activity), do: Activity.locked?(activity)
  defp locked?(_record), do: false

  defp apply_row(team, user, record, row, now) do
    opts = if match?(%Activity{}, record), do: [activity_id: record.id], else: []

    with {:ok, _d4h_id} <- ApplyEdit.call(team, user, row, now, opts) do
      {:ok, copy_values(record, row.new_value["custom_values"])}
    end
  end

  # The record as the sync left it after the write, with the values sent.
  defp copy_values(record, sent) do
    record = App.Repo.reload!(record)

    values =
      (record.custom_values || %{})
      |> Map.merge(sent)
      |> Map.reject(fn {_id, value} -> value == nil end)

    record |> Ecto.Changeset.change(custom_values: values) |> App.Repo.update!()
  end

  @doc """
  `fills` with a template's `values` added for `custom_fields`, the activity's kind's:
  only a field empty on `record` and not in `fills` yet, so what the activity has stays
  and the first template applied wins a field two of them set. A choice keeps only the
  options D4H still offers, as Change fields offers them.
  """
  def fill_empty(fills, record, custom_fields, values) do
    current = record.custom_values || %{}
    values = values || %{}

    Enum.reduce(custom_fields, fills, fn field, fills ->
      id = Integer.to_string(field.d4h_custom_field_id)
      value = live_value(field, values[id])

      if empty?(current[id]) and not Map.has_key?(fills, id) and not empty?(value),
        do: Map.put(fills, id, value),
        else: fills
    end)
  end

  # An option archived or deleted since the template was saved is left out.
  defp live_value(field, ids) when is_list(ids) do
    live = for option <- field.options, not option["archived"], do: option["id"]
    Enum.filter(ids, &(&1 in live))
  end

  defp live_value(_field, value), do: value

  defp empty?(value), do: value in [nil, "", []]

  @doc """
  The change set row for the form's `params` on `record`'s `custom_fields`, or
  `:unchanged`. Only the values that differ go, as `custom_values`, nil to clear one.
  """
  def plan(record, custom_fields, params) do
    current = record.custom_values || %{}

    changed =
      custom_fields
      |> custom_values(params)
      |> Map.reject(fn {id, value} -> current[id] == value end)

    if changed == %{} do
      :unchanged
    else
      old = Map.new(changed, fn {id, _value} -> {id, current[id]} end)
      row(record, %{"custom_values" => old}, %{"custom_values" => changed})
    end
  end

  defp row(%Activity{} = activity, old, new) do
    %ChangeSetRow{
      action: :update_activity,
      d4h_record_id: activity.d4h_activity_id,
      old_value: Map.put(old, "kind", activity.activity_kind),
      new_value: new
    }
  end

  defp row(%Member{} = member, old, new) do
    %ChangeSetRow{
      action: :update_member,
      member_id: member.id,
      d4h_record_id: member.d4h_member_id,
      old_value: old,
      new_value: new
    }
  end

  defp row(%EquipmentItem{} = item, old, new) do
    %ChangeSetRow{
      action: :update_equipment_item,
      d4h_record_id: item.d4h_equipment_id,
      old_value: old,
      new_value: new
    }
  end

  @doc """
  The form's values for `custom_fields`, in what D4H takes: a string, a list of option
  ids for a choice, or nil when empty. A field the form didn't send is left out.
  """
  def custom_values(custom_fields, params) do
    custom_fields
    |> Enum.map(&{Integer.to_string(&1.d4h_custom_field_id), &1})
    |> Enum.filter(fn {id, _field} -> Map.has_key?(params, id) end)
    |> Map.new(fn {id, field} -> {id, custom_value(field, params[id])} end)
  end

  defp custom_value(%CustomField{field_type: type}, value)
       when type in ~w(single_choice multiple_choice) do
    ids =
      value
      |> List.wrap()
      |> Enum.flat_map(fn id ->
        case id |> to_string() |> Integer.parse() do
          {n, ""} -> [n]
          _blank -> []
        end
      end)

    if ids == [], do: nil, else: ids
  end

  defp custom_value(%CustomField{}, value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp custom_value(%CustomField{}, _value), do: nil
end

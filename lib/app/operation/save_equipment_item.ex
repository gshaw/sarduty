defmodule App.Operation.SaveEquipmentItem do
  @moduledoc """
  A team admin adds, changes, or deletes an equipment item of a team on SAR Duty Records
  (#271, docs/records.md). plan/3 turns the form into a change set row, applied through
  App.Operation.ApplyEdit; the sync then copies the item back.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.EquipmentItem
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Repo
  alias App.ViewModel.EquipmentItemFormViewModel

  @doc """
  `{:ok, item}`, `{:error, changeset}` for the form, or `{:error, text}` when Records
  refused the change.
  """
  def call(%Team{} = team, item, params, %User{} = user, now) do
    item = item && Repo.preload(item, :member)
    form = EquipmentItemFormViewModel.from_item(item, team.timezone)

    with {:ok, values} <- EquipmentItemFormViewModel.validate(form, params) do
      item |> plan(values, team.timezone) |> save(team, item, user, now)
    end
  end

  defp save(:unchanged, _team, item, _user, _now), do: {:ok, item}

  defp save(row, team, _item, user, now) do
    with {:ok, id} <- ApplyEdit.call(team, user, row, now),
         do: {:ok, Repo.get_by(EquipmentItem, team_id: team.id, d4h_equipment_id: id)}
  end

  @doc "Deletes an item. `:ok` or `{:error, text}`, such as when items are inside it."
  def delete(%Team{} = team, %EquipmentItem{team_id: team_id} = item, %User{} = user, now)
      when team_id == team.id do
    row = %ChangeSetRow{
      action: :delete_equipment_item,
      d4h_record_id: item.d4h_equipment_id,
      old_value: %{"title" => item.title},
      new_value: %{}
    }

    with {:ok, _id} <- ApplyEdit.call(team, user, row, now), do: :ok
  end

  @doc """
  The change set row for the form's values, or `:unchanged`. An update names only the
  fields that differ, with their old values beside them.
  """
  def plan(nil, %EquipmentItemFormViewModel{} = values, timezone) do
    %ChangeSetRow{
      action: :create_equipment_item,
      old_value: %{},
      new_value: fields(values, timezone)
    }
  end

  def plan(%EquipmentItem{} = item, %EquipmentItemFormViewModel{} = values, timezone) do
    old = item |> EquipmentItemFormViewModel.from_item(timezone) |> fields(timezone)
    new = values |> fields(timezone) |> Map.reject(fn {key, value} -> old[key] == value end)

    if new == %{} do
      :unchanged
    else
      %ChangeSetRow{
        action: :update_equipment_item,
        d4h_record_id: item.d4h_equipment_id,
        old_value: Map.take(old, Map.keys(new)),
        new_value: new
      }
    end
  end

  defp fields(values, timezone) do
    %{
      "title" => values.title,
      "item_type" => values.item_type,
      "status" => values.status,
      "place" => place(values),
      "barcode" => values.barcode,
      "serial" => values.serial,
      "expires_at" =>
        values.expires_on &&
          values.expires_on
          |> Service.Convert.local_to_utc(~T[00:00:00], timezone)
          |> DateTime.to_iso8601()
    }
  end

  defp place(%{place: "new", new_place: title}), do: %{"title" => title}
  defp place(%{place: "Team"}), do: %{"type" => "Team"}

  defp place(%{place: value}) do
    [type, id] = String.split(value, ":")
    %{"type" => type, "id" => String.to_integer(id)}
  end
end

defmodule App.Operation.SaveTemplate do
  @moduledoc """
  Saves or deletes a template (#271). A template is SAR Duty's own, so nothing goes to D4H.

  `lines` are `%{equipment_item_id: id, minutes: n}`, and `tag_ids` and `group_ids` local
  ids (#162). An item, tag, or group that isn't the team's is dropped, so a template never
  points at another team's records.
  """

  import Ecto.Query

  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Model.Template
  alias App.Model.TemplateGroup
  alias App.Model.TemplateItem
  alias App.Model.TemplateTag
  alias App.Operation.SaveCustomFields
  alias App.Repo

  @doc "`{:ok, template}`, or `{:error, changeset}` to show on the form."
  def save(%Team{} = team, template, params, lines, tag_ids \\ [], group_ids \\ []) do
    template =
      template ||
        %Template{team_id: team.id, template_items: [], template_tags: [], template_groups: []}

    template
    |> Template.build_changeset(params)
    |> put_custom_values(team, params["fields"] || %{})
    |> Ecto.Changeset.put_assoc(:template_items, template_items(team, lines))
    |> Ecto.Changeset.put_assoc(:template_tags, template_tags(team, tag_ids))
    |> Ecto.Changeset.put_assoc(:template_groups, template_groups(team, group_ids))
    |> Repo.insert_or_update()
  end

  def delete(%Team{} = team, %Template{team_id: team_id} = template) when team_id == team.id do
    {:ok, _template} = Repo.delete(template)
    :ok
  end

  defp put_custom_values(changeset, team, field_params) do
    values =
      case Ecto.Changeset.get_field(changeset, :activity_kind) do
        nil -> %{}
        kind -> custom_values(CustomField.get_all(team.id, kind), field_params)
      end

    Ecto.Changeset.put_change(changeset, :custom_values, values)
  end

  @doc "The filled values among `field_params` for `custom_fields`, as D4H takes them."
  def custom_values(custom_fields, field_params) do
    custom_fields
    |> SaveCustomFields.custom_values(field_params)
    |> Map.reject(fn {_id, value} -> is_nil(value) end)
  end

  defp template_items(team, lines) do
    lines = Enum.uniq_by(lines, & &1.equipment_item_id)
    ids = Enum.map(lines, & &1.equipment_item_id)

    team_ids =
      EquipmentItem
      |> where([i], i.team_id == ^team.id and i.id in ^ids)
      |> select([i], i.id)
      |> Repo.all()
      |> MapSet.new()

    for line <- lines, MapSet.member?(team_ids, line.equipment_item_id) do
      %TemplateItem{equipment_item_id: line.equipment_item_id, minutes: max(line.minutes || 0, 0)}
    end
  end

  defp template_tags(team, tag_ids) do
    tag_ids = Enum.uniq(tag_ids)

    team_ids =
      Tag
      |> where([t], t.team_id == ^team.id and t.id in ^tag_ids)
      |> select([t], t.id)
      |> Repo.all()
      |> MapSet.new()

    for id <- tag_ids, MapSet.member?(team_ids, id), do: %TemplateTag{tag_id: id}
  end

  defp template_groups(team, group_ids) do
    group_ids = Enum.uniq(group_ids)

    team_ids =
      Group
      |> where([g], g.team_id == ^team.id and g.id in ^group_ids)
      |> select([g], g.id)
      |> Repo.all()
      |> MapSet.new()

    for id <- group_ids, MapSet.member?(team_ids, id), do: %TemplateGroup{group_id: id}
  end
end

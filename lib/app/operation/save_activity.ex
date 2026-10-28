defmodule App.Operation.SaveActivity do
  @moduledoc """
  A team admin adds an activity, or changes its details (docs/records.md, #585). plan/4
  turns the form into a change set row; call/5 applies it through App.Operation.ApplyEdit
  and returns the activity as the sync copied it.

  The hours choice sets the activity's tags: the team's primary or secondary hours tag
  (`Activity.hours_tags/1`), or neither, keeping any other tags it has. The place goes as
  the address text and, when it has a pin, the location (#610). On every team, as
  D4H does: a published activity is locked, so only its published flag changes, and only
  an activity that has finished is published. The description goes as HTML
  (Service.DescriptionHTML), and only when it changed; one the editor can't hold is left
  out. On a D4H team, a new activity has `full_team` and `shared` false, as a chore event
  does (#341), so D4H adds no one's attendance. Records ignores them.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.ChangeSetRow
  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Repo
  alias App.ViewModel.ActivityFormViewModel

  @doc """
  `{:ok, activity}`, `{:error, changeset}` for the form, or `{:error, text}` when the
  store refused the change.
  """
  def call(%Team{} = team, activity, params, %User{} = user, now) do
    form = ActivityFormViewModel.from_activity(activity, team)

    with {:ok, values} <- ActivityFormViewModel.validate(form, params, finished_by(team, now)) do
      tag_ids =
        team
        |> D4H.build_context_from_team()
        |> D4H.fetch_tags()
        |> Map.new(&{&1.title, &1.d4h_tag_id})

      fields = CustomField.get_all(team.id, values.kind)

      case plan(activity, values, tag_ids, team, fields) do
        :unchanged -> {:ok, activity}
        row -> apply_row(team, user, activity, row, now)
      end
    end
  end

  # D4H, and Records with it, refuses to publish an activity that has not happened (409),
  # so the form says so.
  defp finished_by(team, now) do
    {date, time} = Service.Convert.utc_to_local(now, team.timezone)
    [finished_by: NaiveDateTime.new!(date, time)]
  end

  defp apply_row(team, user, activity, row, now) do
    with {:ok, d4h_activity_id} <-
           ApplyEdit.call(team, user, row, now, activity_id: activity && activity.id) do
      saved = Repo.get_by(Activity, team_id: team.id, d4h_activity_id: d4h_activity_id)
      {:ok, copy_custom_values(saved, row.new_value["custom_values"])}
    end
  end

  # D4H doesn't change an activity's updatedAt for its custom fields, so the sync after
  # the write may not read them back (#681). The copy takes what was sent.
  defp copy_custom_values(activity, sent) when activity == nil or sent == nil, do: activity

  defp copy_custom_values(activity, sent) do
    values =
      (activity.custom_values || %{})
      |> Map.merge(sent)
      |> Map.reject(fn {_id, value} -> value == nil end)

    Activity.update!(activity, %{custom_values: values})
  end

  @doc """
  The change set row for the form's values, or `:unchanged`. `tag_ids` maps the team's
  tag titles to their D4H ids. An update names only the fields that differ.
  `custom_fields` are the team's D4H custom fields for the activity's kind (#681): their
  changed values go as `custom_values`, nil to clear one.
  """
  def plan(activity, values, tag_ids, team, custom_fields \\ [])

  def plan(nil, %ActivityFormViewModel{} = values, tag_ids, %Team{} = team, custom_fields) do
    hours_tag_ids = tag_ids_for(values.hours, [], tag_ids, Activity.hours_tags(team))

    custom =
      custom_fields
      |> custom_values(values.custom)
      |> Map.reject(fn {_id, value} -> value == nil end)

    new =
      values
      |> fields(team.timezone)
      |> Map.merge(%{"tag_ids" => hours_tag_ids, "full_team" => false, "shared" => false})
      |> Map.reject(fn {key, value} -> key == "location" and is_nil(value) end)
      |> put_unless_empty("custom_values", custom)

    %ChangeSetRow{
      action: :create_activity,
      old_value: %{},
      new_value: Map.put(new, "kind", values.kind)
    }
  end

  def plan(
        %Activity{} = activity,
        %ActivityFormViewModel{} = values,
        tag_ids,
        %Team{} = team,
        custom_fields
      ) do
    form = ActivityFormViewModel.from_activity(activity, team)
    old = fields(form, team.timezone)

    new =
      values
      |> fields(team.timezone)
      |> Map.reject(fn {key, value} -> old[key] == value end)
      |> drop_locked_description(activity)
      |> put_hours(values.hours != form.hours, activity, values, tag_ids, team)
      |> put_custom(activity, values, custom_fields)
      |> unless_locked(activity)

    if new == %{}, do: :unchanged, else: update_row(activity, old, new)
  end

  # The custom values that differ from the activity's.
  defp put_custom(new, activity, values, custom_fields) do
    current = activity.custom_values || %{}

    changed =
      custom_fields
      |> custom_values(values.custom)
      |> Map.reject(fn {id, value} -> current[id] == value end)

    put_unless_empty(new, "custom_values", changed)
  end

  defp put_unless_empty(map, _key, value) when value == %{}, do: map
  defp put_unless_empty(map, key, value), do: Map.put(map, key, value)

  @doc """
  The form's custom values for `custom_fields`, in what D4H takes: a string, a list of
  option ids for a choice, or nil when empty. A field the form didn't send is left out.
  """
  def custom_values(custom_fields, form_custom) do
    custom_fields
    |> Enum.map(&{Integer.to_string(&1.d4h_custom_field_id), &1})
    |> Enum.filter(fn {id, _field} -> Map.has_key?(form_custom, id) end)
    |> Map.new(fn {id, field} -> {id, custom_value(field, form_custom[id])} end)
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

  # The old description is the one the store had, before cleaning.
  defp update_row(activity, old, new) do
    current = activity.custom_values || %{}
    old_custom = Map.new(new["custom_values"] || %{}, fn {id, _value} -> {id, current[id]} end)

    old =
      old
      |> Map.put("custom_values", old_custom)
      |> Map.take(Map.keys(new))
      |> Map.put("kind", activity.activity_kind)
      |> Map.replace("description", activity.description)

    %ChangeSetRow{
      action: :update_activity,
      d4h_record_id: activity.d4h_activity_id,
      old_value: old,
      new_value: new
    }
  end

  # Only the published flag changes on a locked activity.
  defp unless_locked(new, activity) do
    if Activity.locked?(activity),
      do: Map.take(new, ["published"]),
      else: new
  end

  defp drop_locked_description(new, activity) do
    if ActivityFormViewModel.description_locked?(activity),
      do: Map.delete(new, "description"),
      else: new
  end

  defp put_hours(new, false = _changed?, _activity, _values, _tag_ids, _team), do: new

  defp put_hours(new, true, activity, values, tag_ids, team) do
    hours_tags = Activity.hours_tags(team)
    Map.put(new, "tag_ids", tag_ids_for(values.hours, activity.tags || [], tag_ids, hours_tags))
  end

  defp fields(values, timezone) do
    %{
      "title" => values.title,
      "description" => Service.DescriptionHTML.clean(values.description),
      "place" => values.place,
      "location" => values.coordinate,
      "tracking_number" => values.tracking_number,
      "started_at" => utc(values.starts_at, timezone),
      "finished_at" => utc(values.ends_at, timezone),
      "published" => values.published
    }
  end

  # The activity's other tags, and the chosen hours tag. A tag the team lacks is left out.
  defp tag_ids_for(hours, current_titles, tag_ids, hours_tags) do
    chosen =
      case hours do
        "primary" -> [hours_tags.primary]
        "secondary" -> [hours_tags.secondary]
        "none" -> []
      end

    (current_titles -- [hours_tags.primary, hours_tags.secondary])
    |> Enum.concat(chosen)
    |> Enum.flat_map(&List.wrap(tag_ids[&1]))
    |> Enum.sort()
  end

  defp utc(nil, _timezone), do: nil

  defp utc(%NaiveDateTime{} = naive, timezone) do
    naive
    |> NaiveDateTime.to_date()
    |> Service.Convert.local_to_utc(
      naive |> NaiveDateTime.to_time() |> Time.truncate(:second),
      timezone
    )
    |> DateTime.to_iso8601()
  end
end

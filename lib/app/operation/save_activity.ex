defmodule App.Operation.SaveActivity do
  @moduledoc """
  A team admin adds a hosted team's activity or changes its details
  (docs/hosted-d4h.md). plan/4 turns the form into a change set row; call/5 applies it
  through App.Operation.ApplyEdit and returns the activity as the sync copied it.

  The hours choice sets the activity's tags: Primary Hours, Secondary Hours, or neither,
  keeping any other tags it has.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.ChangeSetRow
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Repo
  alias App.ViewModel.ActivityFormViewModel

  @doc """
  `{:ok, activity}`, `{:error, changeset}` for the form, or `{:error, text}` when the
  store refused the change.
  """
  def call(%Team{} = team, activity, params, %User{} = user, now) do
    form = ActivityFormViewModel.from_activity(activity, team.timezone)

    with {:ok, values} <- ActivityFormViewModel.validate(form, params) do
      tag_ids =
        team
        |> D4H.build_context_from_team()
        |> D4H.fetch_tags()
        |> Map.new(&{&1.title, &1.d4h_tag_id})

      case plan(activity, values, tag_ids, team.timezone) do
        :unchanged -> {:ok, activity}
        row -> apply_row(team, user, activity, row, now)
      end
    end
  end

  defp apply_row(team, user, activity, row, now) do
    with {:ok, d4h_activity_id} <-
           ApplyEdit.call(team, user, row, now, activity_id: activity && activity.id) do
      {:ok, Repo.get_by(Activity, team_id: team.id, d4h_activity_id: d4h_activity_id)}
    end
  end

  @doc """
  The change set row for the form's values, or `:unchanged`. `tag_ids` maps the team's
  tag titles to their D4H ids. An update names only the fields that differ.
  """
  def plan(nil, %ActivityFormViewModel{} = values, tag_ids, timezone) do
    new = values |> fields(timezone) |> Map.put("tag_ids", tag_ids_for(values.hours, [], tag_ids))

    %ChangeSetRow{
      action: :create_activity,
      old_value: %{},
      new_value: Map.put(new, "kind", values.kind)
    }
  end

  def plan(%Activity{} = activity, %ActivityFormViewModel{} = values, tag_ids, timezone) do
    old = activity |> ActivityFormViewModel.from_activity(timezone) |> fields(timezone)
    new = values |> fields(timezone) |> Map.reject(fn {key, value} -> old[key] == value end)

    new =
      if values.hours == ActivityFormViewModel.from_activity(activity, timezone).hours,
        do: new,
        else: Map.put(new, "tag_ids", tag_ids_for(values.hours, activity.tags || [], tag_ids))

    if new == %{} do
      :unchanged
    else
      %ChangeSetRow{
        action: :update_activity,
        d4h_record_id: activity.d4h_activity_id,
        old_value: old |> Map.take(Map.keys(new)) |> Map.put("kind", activity.activity_kind),
        new_value: new
      }
    end
  end

  defp fields(values, timezone) do
    %{
      "title" => values.title,
      "description" => values.description,
      "place" => values.place,
      "tracking_number" => values.tracking_number,
      "started_at" => utc(values.starts_at, timezone),
      "finished_at" => utc(values.ends_at, timezone),
      "published" => values.published
    }
  end

  # The activity's other tags, and the chosen hours tag. A tag the team lacks is left out.
  defp tag_ids_for(hours, current_titles, tag_ids) do
    hours_tags = [Activity.primary_hours_tag(), Activity.secondary_hours_tag()]

    chosen =
      case hours do
        "primary" -> [Activity.primary_hours_tag()]
        "secondary" -> [Activity.secondary_hours_tag()]
        "none" -> []
      end

    (current_titles -- hours_tags)
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

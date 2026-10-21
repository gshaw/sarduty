defmodule App.Operation.SendChoreEvents do
  @moduledoc """
  Sends a team's chore events that need it (#341), each as its own change set of source
  `chores`, applied by SAR Duty itself. Runs nightly after the full refresh
  (App.Worker.SendChoreEventsWorker). A send that does not go through leaves the event
  marked, so the next night tries again.

  D4H is read first only for ids: whether the event is still there and published, and
  each member's attendance row on it. An event deleted in D4H is made again.
  """

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.ChangeSet
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.BuildChoreEvent
  alias App.Repo
  alias Service.ChoreEventText

  @doc "`%{sent: n, failed: n}` for the team's events that needed a send."
  def call(%Team{} = team, now) do
    d4h = D4H.build_context_from_team(team)
    tags = Tag.get_all(team.id)

    team.id
    |> ChoreEvent.get_to_send()
    |> Enum.map(&send_event(team, d4h, tags, &1, now))
    |> Enum.frequencies()
    |> then(&%{sent: Map.get(&1, :sent, 0), failed: Map.get(&1, :failed, 0)})
  end

  defp send_event(team, d4h, tags, event, now) do
    with {:ok, state} <- read_state(d4h, event),
         {:ok, current} <- read_attendance(d4h, state) do
      rows =
        BuildChoreEvent.plan(state, ChoreEvent.accepted_chores(event), current, %{
          title: ChoreEventText.title(event.chore_category.title, event.month),
          month: event.month,
          timezone: team.timezone,
          tag_ids: tag_ids(team, event.chore_category, tags)
        })

      apply_rows(team, event, state, rows, now)
    else
      {:error, error} ->
        ChoreEvent.record_send!(event, event.d4h_activity_id, Exception.message(error), now)
        :failed
    end
  end

  # An event D4H no longer has is made again.
  defp read_state(_d4h, %ChoreEvent{d4h_activity_id: nil}), do: {:ok, nil}

  defp read_state(d4h, %ChoreEvent{d4h_activity_id: id}) do
    case D4H.fetch_activity_tags(d4h, id, "event") do
      {:ok, %{published?: published?}} -> {:ok, %{d4h_activity_id: id, published?: published?}}
      {:error, %D4H.Error{status: 404}} -> {:ok, nil}
      error -> error
    end
  end

  defp read_attendance(_d4h, nil), do: {:ok, []}
  defp read_attendance(d4h, %{d4h_activity_id: id}), do: D4H.fetch_attendance_infos(d4h, id)

  defp apply_rows(_team, event, state, [], now) do
    ChoreEvent.record_send!(event, state && state.d4h_activity_id, nil, now)
    :sent
  end

  defp apply_rows(team, event, state, rows, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :chores,
          summary: ChoreEventText.title(event.chore_category.title, event.month),
          activity_id: local_activity_id(team, state)
        },
        rows
      )

    case ApplyChangeSet.call(team, change_set, nil, now) do
      {:ok, rows} ->
        id = (state && state.d4h_activity_id) || created_id(rows)
        error = rows |> Enum.find(&(&1.status != :applied)) |> then(&(&1 && &1.error))
        ChoreEvent.record_send!(event, id, error, now)
        if error, do: :failed, else: :sent

      {:error, reason} ->
        ChoreEvent.record_send!(event, event.d4h_activity_id, error_text(reason), now)
        :failed
    end
  end

  defp created_id(rows) do
    Enum.find_value(rows, fn row ->
      if row.action == :create_activity and row.status == :applied, do: row.d4h_record_id
    end)
  end

  defp local_activity_id(_team, nil), do: nil

  defp local_activity_id(team, %{d4h_activity_id: id}) do
    case Repo.get_by(Activity, team_id: team.id, d4h_activity_id: id) do
      nil -> nil
      activity -> activity.id
    end
  end

  @doc """
  The D4H tag ids a new event gets: the team's hours tag for the category's hours, by
  title now, and the category's other tags. A tag D4H no longer has is left out.
  """
  def tag_ids(team, %ChoreCategory{} = category, tags) do
    hours_title = Activity.hours_tags(team)[category.hours]
    hours = for tag <- tags, tag.title == hours_title, do: tag.d4h_tag_id
    others = for %{tag: tag} <- category.chore_category_tags, do: tag.d4h_tag_id
    Enum.uniq(Enum.take(hours, 1) ++ others)
  end

  defp error_text(:no_team_key), do: "The team has no D4H access key."
  defp error_text(%D4H.Error{} = error), do: Exception.message(error)
  defp error_text(reason), do: inspect(reason)
end

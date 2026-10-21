defmodule App.Operation.SendChores do
  @moduledoc """
  Sends accepted chores to D4H when a team admin asks (#341). A send makes one D4H event
  for each chore category and year among the chores picked: one category, since an event
  takes one hours tag, and one year, since its date decides which tax credit letter
  counts the hours. `send_changes/4` sends an event again once a sent chore changed.

  Each event is its own change set of source `chores`. D4H is read first only for ids:
  whether the event is still there and published, and each member's attendance row on
  it. An event deleted in D4H is made again. An event whose send did not go through
  keeps its changes to send. One D4H would not publish stays a draft and counts as
  sent, with a note. One D4H has approved is locked: SAR Duty cannot change it again.
  """

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.ChangeSet
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.BuildChoreEvent
  alias App.Repo

  @draft "Left as a draft: D4H would not publish it."
  @approved "Approved in D4H, so SAR Duty cannot change it. Change it in D4H."

  @doc """
  Sends the team's accepted, unsent chores among `ids`. `%{chores: n, events: n,
  failed: n}`: how many chores went, on how many events, and how many events did not go
  through.
  """
  def call(%Team{} = team, ids, user, now) do
    chores =
      Chore
      |> where([c], c.team_id == ^team.id and c.status == :accepted)
      |> where([c], is_nil(c.chore_event_id) and c.id in ^ids)
      |> Repo.all()

    results =
      chores
      |> Enum.group_by(&{&1.chore_category_id, &1.date.year})
      |> Enum.map(fn {key, group} ->
        team |> new_event(key, group) |> send_event_as(team, user, now)
      end)

    %{
      chores: length(chores),
      events: length(results),
      failed: Enum.count(results, &(&1 == :failed))
    }
  end

  # An event for one chore category and year, holding its chores.
  defp new_event(team, {category_id, year}, chores) do
    event = ChoreEvent.create!(team.id, category_id, year)
    ids = Enum.map(chores, & &1.id)
    Chore |> where([c], c.id in ^ids) |> Repo.update_all(set: [chore_event_id: event.id])
    ChoreEvent.find!(team, event.id)
  end

  defp send_event_as(event, team, user, now), do: send_event(team, event, user, now)

  @doc "Sends an event again after its chores changed. `:sent`, `:failed`, or `:locked`."
  def send_changes(%Team{} = team, %ChoreEvent{team_id: team_id} = event, user, now)
      when team_id == team.id,
      do: send_event(team, ChoreEvent.find!(team, event.id), user, now)

  defp send_event(team, event, user, now) do
    d4h = D4H.build_context_from_team(team)

    with {:ok, state} <- read_state(d4h, event),
         :ok <- check_unlocked(event, state),
         {:ok, current} <- read_attendance(d4h, state) do
      rows =
        BuildChoreEvent.plan(state, ChoreEvent.chores(event), current, %{
          category: event.chore_category.title,
          timezone: team.timezone,
          tag_ids: tag_ids(team, event.chore_category, Tag.get_all(team.id))
        })

      apply_rows(team, event, state, rows, user, now)
    else
      :locked ->
        ChoreEvent.record_send!(event, event.d4h_activity_id, {:locked, @approved}, now)
        :locked

      {:error, error} ->
        ChoreEvent.record_send!(event, event.d4h_activity_id, {:failed, error_text(error)}, now)
        :failed
    end
  end

  # D4H refuses changes to an approved activity (#356), so nothing is tried.
  defp check_unlocked(_event, %{approved?: true}), do: :locked
  defp check_unlocked(_event, _state), do: :ok

  # An event D4H no longer has is made again.
  defp read_state(_d4h, %ChoreEvent{d4h_activity_id: nil}), do: {:ok, nil}

  defp read_state(d4h, %ChoreEvent{d4h_activity_id: id}) do
    case D4H.fetch_activity_tags(d4h, id, "event") do
      {:ok, %{published?: published?, approved?: approved?}} ->
        {:ok, %{d4h_activity_id: id, published?: published?, approved?: approved?}}

      {:error, %D4H.Error{status: 404}} ->
        {:ok, nil}

      error ->
        error
    end
  end

  defp read_attendance(_d4h, nil), do: {:ok, []}
  defp read_attendance(d4h, %{d4h_activity_id: id}), do: D4H.fetch_attendance_infos(d4h, id)

  defp apply_rows(_team, event, state, [], _user, now) do
    ChoreEvent.record_send!(event, state && state.d4h_activity_id, :sent, now)
    :sent
  end

  defp apply_rows(team, event, state, rows, user, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :chores,
          summary: "Chores: #{event.chore_category.title}",
          proposed_by_user_id: user.id,
          activity_id: local_activity_id(team, state)
        },
        rows
      )

    case ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, rows} ->
        id = (state && state.d4h_activity_id) || created_id(rows)
        outcome = outcome(rows)
        ChoreEvent.record_send!(event, id, outcome, now)
        if match?({:failed, _error}, outcome), do: :failed, else: :sent

      {:error, reason} ->
        ChoreEvent.record_send!(event, event.d4h_activity_id, {:failed, error_text(reason)}, now)
        :failed
    end
  end

  @doc """
  How a send went, from its rows: `:sent`; `{:sent, note}` when only publishing failed,
  so the event stays a draft; or `{:failed, error}` with the first row's error.
  """
  def outcome(rows) do
    case Enum.reject(rows, &(&1.status == :applied)) do
      [] ->
        :sent

      not_sent ->
        if Enum.all?(not_sent, &publish?/1),
          do: {:sent, @draft},
          else: {:failed, hd(not_sent).error}
    end
  end

  defp publish?(row), do: row.action == :publish_activity and row.new_value["published"] == true

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
  The D4H tag ids a new event gets: the team's hours tag for the chore category's hours,
  by title now, and the category's other tags. A tag D4H no longer has is left out.
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

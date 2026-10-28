defmodule App.Operation.SendChores do
  @moduledoc """
  Brings the team's chore events in D4H up to date (#341). A team admin's accept,
  change, or decline runs it, and so does Send changes on the Chores page. Each chore
  category has one D4H event a month for its accepted chores (App.Model.ChoreEvent),
  however often a team admin accepts them.

  Each send is its own change set of source `chores`. D4H is read first only for ids:
  whether the event is still there and published, and each member's attendance row on
  it. An event deleted in D4H is made again. An event whose send did not go through
  keeps its changes to send, and so does one D4H would not tag; the next send tags an
  event that lacks its hours tag. One D4H would not publish stays a draft and counts as
  sent, with a note. D4H's `approved` flag only mirrors `published` (#358), so nothing
  here reads it.

  A team's sends run one at a time, so two team admins accepting at once cannot make a
  month's event twice. The send runs in the team admin's page, not a job: a team has a
  few events a month, and a lock per node is enough on one machine.
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

  @draft "Left as a draft."
  @untagged "Sent without its tags. Send the changes to try again."

  @doc """
  Puts the team's accepted chores on their events (`ChoreEvent.place!/1`), then sends
  every event with changes. `%{events: n, failed: n}`: how many events it sent, and how
  many of those did not go through. Every event, not just the ones a decision touched,
  so one that failed tries again on each decision and says so until it is fixed.
  """
  def call(%Team{} = team, user, now) do
    :global.trans({{__MODULE__, team.id}, self()}, fn ->
      {:ok, :ok} = Repo.transaction(fn -> ChoreEvent.place!(team.id) end)
      tags = team_tags(team)

      results =
        team.id
        |> ChoreEvent.get_to_send()
        |> Enum.map(&send_event(team, &1, tags, user, now))

      %{events: length(results), failed: Enum.count(results, &(&1 == :failed))}
    end)
  end

  # The team's tags and hours tag titles, read once for a send's events.
  defp team_tags(team), do: %{all: Tag.get_all(team.id), hours: Activity.hours_tags(team)}

  defp send_event(team, event, tags, user, now) do
    d4h = D4H.build_context_from_team(team)
    chores = ChoreEvent.chores(event)

    with {:ok, state} <- read_state(d4h, event),
         {:ok, send_tags} <- send_tags(team, state, chores, event.chore_category, tags),
         {:ok, current} <- read_attendance(d4h, state) do
      rows = plan(team, event, chores, state, current, send_tags)
      apply_rows(team, event, state, rows, user, now)
    else
      {:error, error} ->
        ChoreEvent.record_send!(
          event,
          event.d4h_activity_id,
          {:failed, error_text(team, error)},
          now
        )

        :failed
    end
  end

  defp plan(team, event, chores, state, current, tags) do
    BuildChoreEvent.plan(state, chores, current, %{
      category: event.chore_category.title,
      month: event.month,
      timezone: team.timezone,
      tags: tags
    })
  end

  # A new event needs its hours tag, or its hours count nowhere. A sent one gets its tags
  # again only when it lacks the hours tag: a send whose tags D4H refused. An event with
  # no chores gets none.
  defp send_tags(_team, _state, [], _category, _tags), do: {:ok, []}

  defp send_tags(team, nil, _chores, category, tags) do
    case event_tags(category, tags.hours, tags.all) do
      {:ok, event_tags} ->
        {:ok, event_tags}

      {:error, title} ->
        {:error, "No tag is named #{title}, this category's hours tag. #{add_tag(team)}"}
    end
  end

  defp send_tags(_team, state, _chores, category, tags) do
    case event_tags(category, tags.hours, tags.all) do
      {:ok, [hours | _others] = event_tags} ->
        if hours.d4h_tag_id in state.tag_ids, do: {:ok, []}, else: {:ok, event_tags}

      {:error, _title} ->
        {:ok, []}
    end
  end

  # An event D4H no longer has is made again.
  defp read_state(_d4h, %ChoreEvent{d4h_activity_id: nil}), do: {:ok, nil}

  defp read_state(d4h, %ChoreEvent{d4h_activity_id: id}) do
    case D4H.fetch_activity_tags(d4h, id, "event") do
      {:ok, %{tag_ids: tag_ids, published?: published?}} ->
        {:ok, %{d4h_activity_id: id, tag_ids: tag_ids, published?: published?}}

      {:error, %D4H.Error{status: 404}} ->
        {:ok, nil}

      error ->
        error
    end
  end

  defp read_attendance(_d4h, nil), do: {:ok, []}
  defp read_attendance(d4h, %{d4h_activity_id: id}), do: D4H.fetch_attendance_infos(d4h, id)

  # No chores and nothing in D4H: the event is no longer needed.
  defp apply_rows(_team, event, nil, [], _user, _now) do
    Repo.delete!(event)
    :sent
  end

  defp apply_rows(_team, event, state, [], _user, now) do
    ChoreEvent.record_send!(event, state.d4h_activity_id, :sent, now)
    :sent
  end

  defp apply_rows(team, event, state, rows, user, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :chores,
          summary: ChoreEventText.title(event.chore_category.title, event.month),
          proposed_by_user_id: user.id,
          activity_id: local_activity_id(team, state)
        },
        rows
      )

    case ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, rows} ->
        id = (state && state.d4h_activity_id) || created_id(rows)
        outcome = outcome(team, rows)
        ChoreEvent.record_send!(event, id, outcome, now)
        if match?({:failed, _error}, outcome), do: :failed, else: :sent

      {:error, reason} ->
        ChoreEvent.record_send!(
          event,
          event.d4h_activity_id,
          {:failed, error_text(team, reason)},
          now
        )

        :failed
    end
  end

  @doc """
  How a send went, from its rows: `:sent`; `{:sent, note}` when only publishing failed,
  so the event stays a draft; or `{:failed, error}` with the first row's error.
  """
  def outcome(team, rows) do
    case Enum.reject(rows, &(&1.status == :applied)) do
      [] ->
        :sent

      not_sent ->
        cond do
          Enum.all?(not_sent, &publish?/1) ->
            {:sent, draft(team, hd(not_sent))}

          row = Enum.find(not_sent, &(&1.action == :set_activity_tags)) ->
            {:failed, untagged(row)}

          true ->
            {:failed, hd(not_sent).error}
        end
    end
  end

  defp untagged(row), do: "#{@untagged} #{row.error}"

  defp draft(_team, %{error: nil}), do: @draft

  # D4H's approval step refuses some of South Fraser's publishes from the API, while its
  # own Approve button works (2026-10-28). No setting fixes it, so the note says to approve.
  defp draft(team, row) do
    if row.error =~ "cannot be marked ready for approval or published",
      do: "#{@draft} #{row.error} Approve it in #{D4H.service_name(team)}.",
      else: "#{@draft} #{row.error}"
  end

  # A team on SAR Duty Records has no tags page: its hours tags come with the team.
  defp add_tag(team) do
    if D4H.records?(team),
      do: "Select another hours tag in team settings.",
      else: "Add it in #{D4H.service_name(team)}, or select another hours tag in team settings."
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
  The tags a new event gets: the team's hours tag for the chore category's hours, by
  title now, and the category's other tags. `hours_tags` is `Activity.hours_tags/1`.
  `{:error, title}` when no tag has the hours tag's title.
  """
  def event_tags(%ChoreCategory{} = category, hours_tags, tags) do
    hours_title = hours_tags[category.hours]

    case Enum.find(tags, &(&1.title == hours_title)) do
      nil ->
        {:error, hours_title}

      hours ->
        others = for %{tag: tag} <- category.chore_category_tags, do: tag
        {:ok, Enum.uniq_by([hours | others], & &1.d4h_tag_id)}
    end
  end

  defp error_text(_team, :no_team_key), do: "Your team has no access key."
  defp error_text(team, %D4H.Error{} = error), do: D4H.error_text(team, error)
  defp error_text(_team, text) when is_binary(text), do: text
  defp error_text(_team, reason), do: inspect(reason)
end

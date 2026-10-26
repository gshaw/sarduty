defmodule App.Operation.ProposeActivityTags do
  @moduledoc """
  An AI agent's tag changes on up to 50 activities, saved as one change set that waits for
  a team admin (#595), such as adding the primary hours tag to activities that count no
  hours. Nothing here writes to D4H. Each activity gets one `set_activity_tags` row
  (ChangeActivityTags.plan/4). Drafts only: D4H refuses tags on a published activity
  (#358), and refuses to publish one again once SAR Duty makes it a draft (live,
  2026-10-26). Sending reads each activity's tags again and skips one that changed or was
  published since.

  plan/4 decides the rows, pure; call/4 reads and saves.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.ChangeSet
  alias App.Model.ChoreEvent
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Operation.ChangeActivityTags
  alias App.Repo

  @doc """
  Saves the changes as a waiting change set. `requests` are maps with string keys:
  `activity_id`, `add` and `remove` (lists of tag titles), and `reason`. `{:ok, change_set,
  problems}`, or `{:error, problems}` when nothing would change.
  """
  def call(%Team{} = team, %User{} = user, requests, summary) do
    ids = for r <- requests, is_integer(r["activity_id"]), do: r["activity_id"]

    case plan(
           load_activities(team, ids),
           Tag.get_all(team.id),
           Activity.hours_tags(team),
           requests
         ) do
      {[], problems} ->
        {:error, problems}

      {rows, problems} ->
        change_set =
          ChangeSet.propose!(
            %ChangeSet{
              team_id: team.id,
              source: :agent,
              proposed_by_user_id: user.id,
              summary: summary && String.slice(summary, 0, 255)
            },
            rows
          )

        {:ok, change_set, problems}
    end
  end

  defp load_activities(team, ids) do
    chores = from(c in subquery(ChoreEvent.totals(team.id)), select: c.d4h_activity_id)

    Activity
    |> where([a], a.team_id == ^team.id and a.id in ^ids)
    |> where([a], a.d4h_activity_id not in subquery(chores))
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  @doc """
  The rows for `requests`, and a sentence for each left out. Pure: `activities` are the
  team's activities by id, chore activities left out, `tags` the team's tags, and
  `hours_tags` `Activity.hours_tags/1`. An activity named twice keeps the first request.
  """
  def plan(activities, tags, hours_tags, requests) do
    context = %{
      activities: activities,
      by_title: Map.new(tags, &{String.downcase(&1.title), &1}),
      titles: Map.new(tags, &{&1.d4h_tag_id, &1.title}),
      hours_tags: hours_tags
    }

    {rows, problems, _seen} =
      Enum.reduce(requests, {[], [], MapSet.new()}, &add_request(context, &1, &2))

    {rows |> Enum.reverse() |> List.flatten(), Enum.reverse(problems)}
  end

  defp add_request(context, request, {rows, problems, seen}) do
    case plan_activity(context, seen, request) do
      {:ok, activity_rows, id} -> {[activity_rows | rows], problems, MapSet.put(seen, id)}
      {:problem, text} -> {rows, [text | problems], seen}
    end
  end

  defp plan_activity(context, seen, request) do
    with {:ok, activity} <- fetch_activity(context.activities, seen, request["activity_id"]),
         {:ok, start, final} <- final_tags(context, activity, request) do
      activity
      |> ChangeActivityTags.plan(tag_ids(start), tag_ids(final), context.titles)
      |> with_activity(activity, request)
    end
  end

  # The activity's tags now and after the request: one hours tag at most.
  defp final_tags(context, activity, request) do
    with {:ok, start} <- known_tags(activity, context.by_title),
         {:ok, add} <- titles(request["add"], context.by_title, activity),
         {:ok, remove} <- titles(request["remove"], context.by_title, activity),
         final = Enum.uniq_by((start -- remove) ++ add, & &1.d4h_tag_id),
         :ok <- one_hours_tag(final, context.hours_tags, activity),
         do: {:ok, start, final}
  end

  defp tag_ids(tags), do: Enum.map(tags, & &1.d4h_tag_id)

  defp with_activity(:unchanged, activity, _request),
    do: {:problem, "#{activity.title} has those tags already. Nothing to change."}

  defp with_activity(row, activity, request) do
    new_value = Map.put(row.new_value, "activity_title", activity.title)
    row = %{row | reason: reason(request), new_value: new_value}
    {:ok, [row], activity.id}
  end

  defp fetch_activity(activities, seen, id) do
    case Map.get(activities, id) do
      nil ->
        {:problem, "No activity #{inspect(id)} on this team, or it is a chore activity."}

      %Activity{deleted_at: %DateTime{}} = a ->
        {:problem, "#{a.title} is deleted."}

      %Activity{is_published: true} = a ->
        {:problem, "#{a.title} is published. Its tags cannot change."}

      a ->
        if MapSet.member?(seen, id),
          do: {:problem, "#{a.title} is in the list twice. The first one is kept."},
          else: {:ok, a}
    end
  end

  # The activity's tags as the team's tags. D4H replaces the whole list, so a tag the
  # copy can't name would be lost.
  defp known_tags(activity, by_title) do
    {known, unknown} =
      (activity.tags || [])
      |> Enum.map(&{&1, Map.get(by_title, String.downcase(&1))})
      |> Enum.split_with(fn {_title, tag} -> tag end)

    if unknown == [],
      do: {:ok, Enum.map(known, &elem(&1, 1))},
      else:
        {:problem,
         "#{activity.title} has a tag SAR Duty does not know yet. Try after the next refresh."}
  end

  defp titles(nil, _by_title, _activity), do: {:ok, []}

  defp titles(list, by_title, activity) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn title, {:ok, tags} ->
      case find_tag(by_title, title, activity) do
        {:ok, tag} -> {:cont, {:ok, [tag | tags]}}
        problem -> {:halt, problem}
      end
    end)
    |> then(fn
      {:ok, tags} -> {:ok, Enum.reverse(tags)}
      problem -> problem
    end)
  end

  defp titles(_other, _by_title, activity),
    do: {:problem, "Give add and remove as lists of tag titles, for #{activity.title}."}

  defp find_tag(by_title, title, activity) when is_binary(title) do
    case Map.get(by_title, title |> String.trim() |> String.downcase()) do
      nil -> {:problem, "No tag #{inspect(title)} on this team, for #{activity.title}."}
      tag -> {:ok, tag}
    end
  end

  defp find_tag(_by_title, _title, activity),
    do: {:problem, "Give tags as titles, for #{activity.title}."}

  defp one_hours_tag(tags, hours_tags, activity) do
    titles = Enum.map(tags, & &1.title)

    if hours_tags.primary in titles and hours_tags.secondary in titles,
      do: {:problem, "#{activity.title} would have both hours tags. Remove one."},
      else: :ok
  end

  defp reason(%{"reason" => reason}) when is_binary(reason) and reason != "",
    do: String.slice(reason, 0, 255)

  defp reason(_request), do: "Proposed by an AI agent"
end

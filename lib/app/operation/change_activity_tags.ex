defmodule App.Operation.ChangeActivityTags do
  @moduledoc """
  Sets an activity's tags in D4H from its tags page (#323): its hours tag and any others.
  The page reads the tags from D4H as it opens (current/2). Saving is a change set of
  source `:tags` with one `set_activity_tags` row, applied at once. ApplyChangeSet reads
  the tags again first and skips the row when they changed since the page opened.

  plan/3 decides the row; call/6 writes it.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Repo

  @doc """
  The activity's D4H tag ids now. `{:ok, ids}`, `:published` when D4H has published it and
  won't take tags (#358), or `{:error, text}` to show. The local copy takes D4H's published
  flag, so the activity's page agrees before the next refresh.
  """
  def current(%Team{d4h_access_key: nil} = team, _activity),
    do: {:error, describe(team, :no_team_key)}

  def current(%Team{} = team, %Activity{} = activity) do
    d4h = D4H.build_context_from_team(team)

    case D4H.fetch_activity_tags(d4h, activity.d4h_activity_id, activity.activity_kind) do
      {:ok, %{published?: published?} = now} ->
        activity = copy_published(activity, published?)

        if Activity.locked?(activity),
          do: :published,
          else: {:ok, now.tag_ids |> Enum.uniq() |> Enum.sort()}

      {:error, error} ->
        {:error, describe(team, error)}
    end
  end

  defp copy_published(%Activity{is_published: published?} = activity, published?), do: activity

  defp copy_published(activity, published?),
    do: activity |> Ecto.Changeset.change(is_published: published?) |> Repo.update!()

  @doc """
  The row that changes the activity's tags from `start_ids`, read when the page opened,
  to `tag_ids`, or `:unchanged`. `titles` maps a tag id to its title, for the history.
  D4H replaces the whole list, so the row sends every tag the activity keeps, each once.
  """
  def plan(%Activity{} = activity, start_ids, tag_ids, titles \\ %{}) do
    start_ids = start_ids |> Enum.uniq() |> Enum.sort()
    tag_ids = tag_ids |> Enum.uniq() |> Enum.sort()

    if start_ids == tag_ids do
      :unchanged
    else
      title = &Map.get(titles, &1, "Tag #{&1}")

      %ChangeSetRow{
        action: :set_activity_tags,
        d4h_record_id: activity.d4h_activity_id,
        old_value: %{"kind" => activity.activity_kind, "tag_ids" => start_ids},
        new_value: %{
          "tag_ids" => tag_ids,
          "titles" => Enum.map(tag_ids -- start_ids, title),
          "removed_titles" => Enum.map(start_ids -- tag_ids, title)
        }
      }
    end
  end

  @doc """
  Saves `tag_ids` as the activity's tags. `{:ok, row}` with the row as recorded,
  `:unchanged`, or `{:error, text}` to show.
  """
  def call(%Team{} = team, %Activity{} = activity, start_ids, tag_ids, %User{} = user, now)
      when activity.team_id == team.id do
    tags = Tag.get_all(team.id)
    titles = Map.new(tags, &{&1.d4h_tag_id, &1.title})

    case plan(activity, start_ids, tag_ids, titles) do
      :unchanged -> :unchanged
      row -> apply_row(team, activity, row, titles, user, now)
    end
  end

  defp apply_row(team, activity, row, titles, user, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :tags,
          activity_id: activity.id,
          proposed_by_user_id: user.id
        },
        [row]
      )

    case ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, [%ChangeSetRow{status: :applied} = row]} ->
        copy_tags(activity, row, titles)
        {:ok, row}

      {:ok, [row]} ->
        {:ok, row}

      {:error, reason} ->
        {:error, describe(team, reason)}
    end
  end

  # The activity's page shows the new tags before the next refresh. A tag the refresh hasn't
  # copied yet has no title here; the refresh fills it in.
  defp copy_tags(activity, row, titles) do
    tags = row.new_value["tag_ids"] |> Enum.flat_map(&List.wrap(titles[&1])) |> Enum.sort()
    activity |> Ecto.Changeset.change(tags: tags) |> Repo.update!()
  end

  defp describe(_team, :no_team_key), do: "Save your team's access key in team settings first."
  defp describe(_team, :deleted), do: "This activity is deleted."

  defp describe(team, error), do: D4H.error_text(team, error)
end

defmodule App.Operation.SaveLocationBookmark do
  @moduledoc """
  A team admin on SAR Duty Records adds, changes, or deletes a saved place (#614): one
  change set row through App.Operation.ApplyEdit, which refuses a D4H team, whose
  bookmarks change only in D4H. The sync after the edit copies the bookmark here.

  A delete is allowed for a place past activities used: each keeps its own address and
  pin.
  """

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.ChangeSetRow
  alias App.Model.LocationBookmark
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Repo
  alias App.ViewModel.LocationBookmarkFormViewModel

  @doc """
  Adds (`bookmark` nil) or changes a saved place. `{:ok, title}`, `{:error, changeset}`
  for the form, or `{:error, text}`.
  """
  def save(%Team{} = team, bookmark, params, %User{} = user, now) do
    with :ok <- check_team(team, bookmark),
         {:ok, form} <-
           bookmark
           |> LocationBookmarkFormViewModel.from_bookmark()
           |> LocationBookmarkFormViewModel.changeset(params)
           |> Ecto.Changeset.apply_action(:insert),
         {:ok, _id} <-
           ApplyEdit.call(
             team,
             user,
             plan(bookmark, LocationBookmarkFormViewModel.value(form)),
             now
           ) do
      {:ok, form.title}
    end
  end

  @doc "The row that adds or changes a bookmark to `new_value`."
  def plan(nil, new_value),
    do: %ChangeSetRow{action: :create_location_bookmark, old_value: %{}, new_value: new_value}

  def plan(%LocationBookmark{} = bookmark, new_value) do
    %ChangeSetRow{
      action: :update_location_bookmark,
      d4h_record_id: bookmark.d4h_location_bookmark_id,
      old_value: value(bookmark),
      new_value: new_value
    }
  end

  @doc "Deletes a saved place. `:ok` or `{:error, text}`."
  def delete(%Team{} = team, %LocationBookmark{} = bookmark, %User{} = user, now) do
    row = %ChangeSetRow{
      action: :delete_location_bookmark,
      d4h_record_id: bookmark.d4h_location_bookmark_id,
      old_value: value(bookmark),
      new_value: %{}
    }

    with :ok <- check_team(team, bookmark),
         {:ok, _id} <- ApplyEdit.call(team, user, row, now) do
      Repo.delete(bookmark, allow_stale: true)
      :ok
    end
  end

  defp value(bookmark) do
    %{
      "title" => bookmark.title,
      "place" => bookmark.address,
      "location" => Activity.pin(bookmark)
    }
  end

  defp check_team(_team, nil), do: :ok
  defp check_team(%Team{id: id}, %LocationBookmark{team_id: id}), do: :ok
end

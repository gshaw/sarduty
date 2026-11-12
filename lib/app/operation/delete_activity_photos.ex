defmodule App.Operation.DeleteActivityPhotos do
  @moduledoc """
  A team admin deletes photos that wait on an activity (#1032): the row and its three
  files, for good. A photo's files go first, so a row that is gone never leaves a file
  behind; one whose files did not delete stays, to delete again.
  """

  alias App.Adapter.FileStore
  alias App.Model.Activity
  alias App.Model.ActivityPhoto
  alias App.Model.Team
  alias App.Repo

  require Logger

  @doc """
  Deletes the activity's waiting photos among `ids`, which come from the browser: only
  the team's, on this activity, and still waiting (ActivityPhoto.waiting_among/3).
  `{:ok, %{deleted:, kept:}}`, counts: `kept` are the ones the file store refused.
  """
  def call(%Team{} = team, %Activity{} = activity, ids) when is_list(ids) do
    results =
      team |> ActivityPhoto.waiting_among(activity, ids) |> Repo.all() |> Enum.map(&delete/1)

    deleted = Enum.count(results, &(&1 == :ok))
    {:ok, %{deleted: deleted, kept: length(results) - deleted}}
  end

  defp delete(%ActivityPhoto{} = photo) do
    case delete_files(photo) do
      :ok ->
        Repo.delete!(photo)
        :ok

      error ->
        Logger.error("An activity photo's files did not delete: #{inspect(error)}")
        :kept
    end
  end

  defp delete_files(photo) do
    photo
    |> ActivityPhoto.keys()
    |> Enum.reduce_while(:ok, fn {_size, key}, :ok ->
      case FileStore.delete(key) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end

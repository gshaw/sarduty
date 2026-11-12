defmodule App.Operation.DeleteActivityPhoto do
  @moduledoc """
  A team admin deletes one activity photo, waiting or accepted (#1033): the row, its
  stars, and its three files, for good. It is how a photo is taken down when someone in
  it asks. The files go first, so a row that is gone never leaves a file behind; a photo
  whose files did not delete stays, to delete again.
  """

  alias App.Adapter.FileStore
  alias App.Model.ActivityPhoto
  alias App.Model.Team
  alias App.Repo

  require Logger

  @doc """
  Deletes the photo, looked up again through `team`, so another team's is never
  touched. `:ok`, also for one that is gone already, or `{:error, :files}` when the file
  store refused: the photo stays.
  """
  def call(%Team{id: team_id}, %ActivityPhoto{id: id}) do
    case Repo.get_by(ActivityPhoto, id: id, team_id: team_id) do
      nil -> :ok
      photo -> delete(photo)
    end
  end

  defp delete(photo) do
    case delete_files(photo) do
      :ok ->
        # Its stars go with the row: the table's key deletes them.
        Repo.delete!(photo)
        :ok

      error ->
        Logger.error("An activity photo's files did not delete: #{inspect(error)}")
        {:error, :files}
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

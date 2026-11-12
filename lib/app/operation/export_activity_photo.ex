defmodule App.Operation.ExportActivityPhoto do
  @moduledoc """
  Export for a post (#1032, part 9): a team admin takes a copy of an accepted photo the
  team may post, in the shape a post needs (Service.PhotoExport). It starts from the
  photo as edited: the original at its full size with the turns and the straightened
  cut, or for a photo with Clean up on, the cleaned-up copy to show, the only one Clean
  up made.

  Nothing is saved: not the box, not the export, and the photo does not change. It runs
  inline, as the team admin waits for the file (docs/jobs.md).
  """

  alias App.Adapter.FileStore
  alias App.Model.ActivityPhoto
  alias App.Model.Team

  require Logger

  @doc """
  Pure. Whether the photo can be exported: `:ok`, `{:error, :waiting}` before a team
  admin accepts it, or `{:error, :may_not_post}` when whoever added it did not give the
  team permission to post it.
  """
  def check(%ActivityPhoto{status: status}) when status != :accepted, do: {:error, :waiting}
  def check(%ActivityPhoto{may_post: true}), do: :ok
  def check(%ActivityPhoto{}), do: {:error, :may_not_post}

  @doc """
  Pure. The size of the photo an export starts from, `{width, height}`: what Original
  downloads at, with the box zoomed all the way out.
  """
  def size(%ActivityPhoto{clean_up: true} = photo),
    do: photo |> settings() |> Service.ActivityPhoto.edited_size({photo.width, photo.height}) |> Service.ActivityPhoto.show_size()

  def size(%ActivityPhoto{} = photo),
    do: photo |> settings() |> Service.ActivityPhoto.edited_size({photo.width, photo.height})

  defp settings(photo), do: Map.take(photo, [:turns, :angle, :clean_up])

  @doc """
  The export of the team's photo `id`: `shape`, a key from Service.PhotoExport.shapes/0,
  and `box`, `%{x:, y:, side:}` as placed. `{:ok, jpeg}`, or `{:error, reason}`:
  `:waiting` or `:may_not_post` as check/1 says, or `:files` when the photo cannot be
  read. Raises when the team has no such photo, so the route is not found.
  """
  def call(%Team{} = team, id, shape, box) do
    photo = ActivityPhoto.find_accepted!(team, id, %{team_admin?: true, member: nil})

    with :ok <- check(photo),
         {:ok, image} <- edited(photo),
         {:ok, jpeg} <- Service.PhotoExport.export(image, Service.PhotoExport.shape(shape), box) do
      {:ok, jpeg}
    else
      {:error, reason} when reason in [:waiting, :may_not_post] ->
        {:error, reason}

      error ->
        Logger.error("An activity photo did not export: #{inspect(error)}")
        {:error, :files}
    end
  end

  # The photo as the team sees it, as large as it comes.
  defp edited(%ActivityPhoto{clean_up: true} = photo) do
    with {:ok, show} <- photo |> ActivityPhoto.key(:show) |> FileStore.get(),
         do: Image.from_binary(show)
  end

  defp edited(%ActivityPhoto{} = photo) do
    steps = photo |> settings() |> Service.ActivityPhoto.plan({photo.width, photo.height})

    with {:ok, original} <- photo |> ActivityPhoto.key(:original) |> FileStore.get(),
         do: Service.ActivityPhoto.edited(original, steps)
  end
end

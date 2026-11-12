defmodule App.Operation.EditActivityPhoto do
  @moduledoc """
  A team admin edits an accepted activity photo (#1032, part 8): quarter turns, an angle
  to straighten it, and Clean up. The settings go on the row, and the copies to show and
  for tiles are made again from the original with them
  (Service.ActivityPhoto.plan/2 and edit/3). The original is never changed, so Download
  original still gives the photo as it came, and `revert/3` brings the copies back.

  One edit, or none: saving replaces the last, and there is no history. Clean up runs
  inline, as the team admin waits for it (docs/jobs.md), through App.Adapter.CleanUp.
  When it does not answer, the photo saves without it.
  """

  alias App.Accounts.User
  alias App.Adapter.CleanUp
  alias App.Adapter.FileStore
  alias App.Model.ActivityPhoto
  alias App.Model.Team
  alias App.Repo

  require Logger

  # The cleaned-up photo Edit photo shows while the team admin decides: big enough to
  # judge the light by, small enough to send to the page.
  @preview_side 1200

  @doc "Whether Clean up runs at all. With it off, Edit photo has no switch."
  def clean_up_available?, do: CleanUp.available?()

  @doc "Pure. Whether the photo can be edited: `:ok`, or `{:error, :waiting}` before a team admin accepts it."
  def check(%ActivityPhoto{status: :accepted}), do: :ok
  def check(%ActivityPhoto{}), do: {:error, :waiting}

  @doc """
  Saves `settings`, `%{turns:, angle:, clean_up:}`, on the team's photo, and makes its
  copies again from the original. Settings with nothing to do clear the edit.
  `{:ok, photo}`, whose `clean_up` is false when Clean up did not answer; or
  `{:error, reason}` with nothing changed: `:waiting`, `:gone` for a photo deleted
  since, or `:files` when the original cannot be read or the copies did not save.
  """
  def call(%Team{} = team, %ActivityPhoto{} = photo, settings, user, %DateTime{} = now)
      when is_struct(user, User) or is_nil(user) do
    settings = settings(settings)

    # The row as it is now, through its team: the page may hold an older one.
    with %ActivityPhoto{} = photo <- Repo.get_by(ActivityPhoto, id: photo.id, team_id: team.id),
         :ok <- check(photo),
         {:ok, files} <- copies(photo, settings),
         :ok <- put(photo, files) do
      save(photo, %{settings | clean_up: files.cleaned?}, user, now)
    else
      nil -> {:error, :gone}
      {:error, _reason} = error -> error
    end
  end

  # Clean up only where it runs.
  defp settings(settings) do
    settings = Service.ActivityPhoto.settings(settings)
    %{settings | clean_up: settings.clean_up and clean_up_available?()}
  end

  # The settings the copies were made with. Who and when only for an edit.
  defp save(photo, settings, user, now) do
    edited? = Service.ActivityPhoto.plan(settings, {photo.width, photo.height}) != []

    photo
    |> Ecto.Changeset.change(Map.take(settings, [:turns, :angle, :clean_up]))
    |> Ecto.Changeset.change(
      edited_by_user_id: if(edited?, do: user && user.id),
      edited_at: if(edited?, do: now)
    )
    # Always a new updated_at: the files' URLs carry it, so no browser keeps the old copies.
    |> Repo.update(force: true)
  end

  @doc "Revert to original: clears the edit and makes the copies again as they came."
  def revert(%Team{} = team, %ActivityPhoto{} = photo, %DateTime{} = now),
    do: call(team, photo, %{turns: 0, angle: 0, clean_up: false}, nil, now)

  # The copies for the settings, from the original.
  defp copies(photo, settings) do
    steps = Service.ActivityPhoto.plan(settings, {photo.width, photo.height})

    with {:ok, original} <- original(photo),
         {:ok, files} <- Service.ActivityPhoto.edit(original, steps, &clean_up/1) do
      {:ok, files}
    else
      error ->
        Logger.error("An activity photo did not edit: #{inspect(error)}")
        {:error, :files}
    end
  end

  defp clean_up(jpeg) do
    case CleanUp.call(jpeg, :activity) do
      {:ok, %{bytes: bytes}} -> {:ok, bytes}
      error -> error
    end
  end

  defp put(photo, files) do
    with :ok <- photo |> ActivityPhoto.key(:show) |> FileStore.put(files.show),
         :ok <- photo |> ActivityPhoto.key(:tile) |> FileStore.put(files.tile) do
      :ok
    else
      error ->
        Logger.error("An activity photo's copies did not save: #{inspect(error)}")
        {:error, :files}
    end
  end

  defp original(photo), do: photo |> ActivityPhoto.key(:original) |> FileStore.get()

  @doc """
  The photo as Clean up returns it, for Edit photo to show beside the switch: the
  original, at up to 1200 px, before any turn. `{:ok, jpeg}`, or `{:error, reason}`
  when Clean up is off or did not answer.
  """
  def preview(%ActivityPhoto{} = photo) do
    with {:ok, original} <- original(photo),
         {:ok, jpeg} <- Service.Image.jpeg(original, @preview_side),
         {:ok, %{bytes: bytes}} <- CleanUp.call(jpeg, :activity) do
      {:ok, bytes}
    end
  end
end

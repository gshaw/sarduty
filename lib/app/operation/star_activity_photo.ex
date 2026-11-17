defmodule App.Operation.StarActivityPhoto do
  @moduledoc """
  Someone on the team stars an accepted activity photo, or takes their star back
  (#1033). One star each: starring a photo you starred removes it. A waiting photo
  takes no stars, since the team does not see it yet.
  """

  alias App.Accounts.User
  alias App.Model.ActivityPhoto
  alias App.Model.ActivityPhotoStar
  alias App.Repo

  @doc """
  Flips `user`'s star on the photo. `{:ok, starred?}`, whether they star it now, or
  `{:error, :waiting}` for a photo no team admin has accepted.
  """
  def call(%ActivityPhoto{status: :accepted} = photo, %User{} = user) do
    case photo |> ActivityPhotoStar.of(user) |> Repo.delete_all() do
      {0, _rows} ->
        # A second tab that starred it first leaves the one star.
        Repo.insert!(
          %ActivityPhotoStar{
            team_id: photo.team_id,
            activity_photo_id: photo.id,
            user_id: user.id
          },
          on_conflict: :nothing
        )

        {:ok, true}

      {_removed, _rows} ->
        {:ok, false}
    end
  end

  def call(%ActivityPhoto{}, %User{}), do: {:error, :waiting}
end

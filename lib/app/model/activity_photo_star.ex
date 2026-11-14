defmodule App.Model.ActivityPhotoStar do
  use App, :model

  alias App.Accounts.User
  alias App.Model.ActivityPhoto
  alias App.Model.ActivityPhotoStar
  alias App.Model.Team
  alias App.Repo

  # One login's star on an accepted activity photo (#1033). One each: the pair is
  # unique, and starring again takes it away (App.Operation.StarActivityPhoto). A photo
  # shows how many it has, and each person whether theirs is among them. Who starred is
  # never shown, so nothing lists these rows by person for anyone else. A team admin
  # viewing as a member sees their own stars, not the member's.
  schema "activity_photo_stars" do
    belongs_to :team, Team
    belongs_to :activity_photo, ActivityPhoto
    belongs_to :user, User
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "The user's star on the photo, as a query: one row or none."
  def of(%ActivityPhoto{id: photo_id, team_id: team_id}, %User{id: user_id}) do
    where(
      ActivityPhotoStar,
      [s],
      s.team_id == ^team_id and s.activity_photo_id == ^photo_id and s.user_id == ^user_id
    )
  end

  @doc "How many stars each of the photos has, as `%{photo_id => count}`. None is no key."
  def counts(photo_ids) when is_list(photo_ids) do
    ActivityPhotoStar
    |> where([s], s.activity_photo_id in ^photo_ids)
    |> group_by([s], s.activity_photo_id)
    |> select([s], {s.activity_photo_id, count(s.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Which of the photos the user starred, as a set of photo ids."
  def starred_by(%User{id: user_id}, photo_ids) when is_list(photo_ids) do
    ActivityPhotoStar
    |> where([s], s.user_id == ^user_id and s.activity_photo_id in ^photo_ids)
    |> select([s], s.activity_photo_id)
    |> Repo.all()
    |> MapSet.new()
  end
end

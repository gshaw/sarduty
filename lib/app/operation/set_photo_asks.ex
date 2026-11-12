defmodule App.Operation.SetPhotoAsks do
  @moduledoc """
  Turns a member's photo asks on or off (#1034), from account settings: whether a team
  admin's ask for their photos from an activity emails them
  (App.Operation.AskForActivityPhotos). An ask for a photo of them, for their ID card,
  is not covered: the team needs that one. SAR Duty's own setting; nothing goes to the
  team's records.
  """
  alias App.Model.Member
  alias App.Repo

  def call(%Member{} = member, on?) when is_boolean(on?) do
    member |> Ecto.Changeset.change(photo_asks: on?) |> Repo.update!()
  end
end

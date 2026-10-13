defmodule App.Operation.SetMapsApp do
  @moduledoc """
  Saves the maps app a person's place links open: "google" or "apple" (#301).
  """

  alias App.Accounts.User
  alias App.Repo

  def call(%User{} = user, app) do
    user |> User.maps_app_changeset(%{maps_app: app}) |> Repo.update()
  end
end

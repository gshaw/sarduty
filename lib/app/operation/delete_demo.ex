defmodule App.Operation.DeleteDemo do
  @moduledoc """
  Deletes a Try a demo (#857), from Delete this demo on its banner or when its time is up:
  both its teams in SAR Duty and Records (App.Operation.DeleteTeam.purge/2), its copy of
  WESARA (#963), its row with the visitor's name, and the user its link logged in as.
  """

  alias App.Accounts.User
  alias App.Model.DemoTeam
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.DeleteTeam
  alias App.Repo

  @doc "`:ok`, or `{:error, reason}` with the demo kept for the next try."
  # Silver Basin first: Coast Range's delete takes the demo's row with it, so a failure
  # after that would leave Silver Basin with no row to find it by.
  def call(%DemoTeam{} = demo) do
    with :ok <- delete_team(demo.second_team_id),
         :ok <- delete_team(demo.team_id) do
      delete_organization(demo.organization_id)
      if Repo.reload(demo), do: Repo.delete!(demo)
      delete_user(demo.user_id)
      :ok
    end
  end

  defp delete_team(nil), do: :ok

  defp delete_team(team_id) do
    case Repo.get(Team, team_id) do
      nil ->
        :ok

      team ->
        with {:ok, _result} <- DeleteTeam.purge(team, reason: :demo), do: :ok
    end
  end

  # Its admins go with it.
  defp delete_organization(nil), do: :ok

  defp delete_organization(id) do
    if organization = Repo.get(Organization, id), do: Repo.delete!(organization)
    :ok
  end

  # Its own user, made for it with an example.com email, so it leads nowhere else.
  defp delete_user(nil), do: :ok

  defp delete_user(user_id) do
    case Repo.get(User, user_id) do
      %User{is_admin: false} = user -> Repo.delete!(user)
      _admin_or_none -> :ok
    end

    :ok
  end
end

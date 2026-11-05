defmodule App.Operation.DeleteDemo do
  @moduledoc """
  Deletes a Try a demo (#857), from Delete this demo on its banner or when its time is up:
  its team in SAR Duty and Records (App.Operation.DeleteTeam.purge/2), its row with the visitor's
  name, and the user its link logged in as.
  """

  alias App.Accounts.User
  alias App.Model.DemoTeam
  alias App.Model.Team
  alias App.Operation.DeleteTeam
  alias App.Repo

  @doc "`:ok`, or `{:error, reason}` with the demo kept for the next try."
  def call(%DemoTeam{} = demo) do
    with :ok <- delete_team(demo) do
      if Repo.reload(demo), do: Repo.delete!(demo)
      delete_user(demo.user_id)
      :ok
    end
  end

  # DeleteTeam takes the demo's row with the team.
  defp delete_team(%DemoTeam{team_id: nil}), do: :ok

  defp delete_team(%DemoTeam{team_id: team_id}) do
    case Repo.get(Team, team_id) do
      nil ->
        :ok

      team ->
        with {:ok, _result} <- DeleteTeam.purge(team, reason: :demo), do: :ok
    end
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

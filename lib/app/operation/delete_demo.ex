defmodule App.Operation.DeleteDemo do
  @moduledoc """
  Deletes a Try a demo (#857), from Delete this demo on its banner or on its seventh day:
  its team in SAR Duty and Records (App.Operation.DeleteTeam), its row with the visitor's
  name and email, and the visitor's user unless they are on a real team too.
  """

  alias App.Accounts
  alias App.Accounts.User
  alias App.Model.DemoTeam
  alias App.Model.Team
  alias App.Operation.DeleteTeam
  alias App.Repo

  @doc "`:ok`, or `{:error, reason}` with the demo kept for the next try."
  def call(%DemoTeam{} = demo) do
    with :ok <- delete_team(demo) do
      if Repo.reload(demo), do: Repo.delete!(demo)
      delete_user(demo.email)
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
        with {:ok, _team} <- DeleteTeam.call(team, records: :delete_demo), do: :ok
    end
  end

  # A user is only an email. One that still leads somewhere stays.
  defp delete_user(email) do
    case Accounts.get_user_by_email(email) do
      %User{is_admin: false} = user -> if !Accounts.may_log_in?(email), do: Repo.delete!(user)
      _admin_or_none -> :ok
    end

    :ok
  end
end

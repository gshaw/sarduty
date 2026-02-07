# TODO: Remove this module once all teams have their own d4h_access_key.
# This is a temporary fallback that finds a user's PAT when the team doesn't have one.
defmodule App.Operation.RefreshD4HData.ResolveAccessKey do
  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Team
  alias App.Repo

  @doc """
  Returns a D4H access key for the given team.
  Prefers the team's own key, falling back to any user on the team that has one.
  """
  def call(%Team{} = team) do
    case team.d4h_access_key do
      key when is_binary(key) and key != "" -> key
      _ -> find_user_access_key(team)
    end
  end

  defp find_user_access_key(team) do
    User
    |> where([u], u.team_id == ^team.id)
    |> where([u], not is_nil(u.d4h_access_key) and u.d4h_access_key != "")
    |> limit(1)
    |> select([u], u.d4h_access_key)
    |> Repo.one()
  end
end

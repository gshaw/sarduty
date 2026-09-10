# TODO: Remove the member fallback once all teams have their own d4h_access_key (#41).
defmodule App.Operation.RefreshD4HData.ResolveAccessKey do
  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Team
  alias App.Repo

  @doc """
  Returns `{owner, access_key}` for the key the refresh uses, where `owner` is `:team` or
  the `%User{}` whose personal key is borrowed, or `nil` when there is no key.
  """
  def call(%Team{} = team) do
    users = User |> where([u], u.team_id == ^team.id) |> Repo.all()

    case key_owner(team, users) do
      nil -> nil
      :team -> {:team, team.d4h_access_key}
      %User{} = user -> {user, user.d4h_access_key}
    end
  end

  @doc """
  The team's own key when it has one, otherwise the personal key of the earliest member
  (lowest user id) who has one, otherwise `nil`.
  """
  def key_owner(%Team{} = team, users) do
    if key?(team.d4h_access_key) do
      :team
    else
      users
      |> Enum.filter(&key?(&1.d4h_access_key))
      |> Enum.min_by(& &1.id, fn -> nil end)
    end
  end

  def key?(key), do: is_binary(key) and key != ""
end

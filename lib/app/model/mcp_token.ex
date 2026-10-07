defmodule App.Model.MCPToken do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.MCPToken
  alias App.Model.Team
  alias App.Repo

  # A manager's personal token for the MCP endpoint (#28). It belongs to a user and a
  # team. The database keeps only its SHA-256 hash, so a copy of the database can't be
  # used to call the endpoint. 32 random bytes need no keyed hash, unlike a login code.
  # The prefix lets secret scanners spot a leaked token.
  @prefix "sarduty_mcp_"
  @rand_size 32

  schema "mcp_tokens" do
    belongs_to :team, Team
    belongs_to :user, User
    field :name, TrimmedString
    field :token_hash, :binary, redact: true
    field :last_used_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  A new token for `user` on `team`: the token to show once, and the changeset to insert.
  """
  def build(%Team{} = team, %User{} = user, params) do
    token = @rand_size |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    token = @prefix <> token

    changeset =
      %MCPToken{team_id: team.id, user_id: user.id, token_hash: hash(token)}
      |> cast(params, [:name])
      |> validate_required([:name], message: "Enter a name for the token")
      |> validate_length(:name, max: 60, message: "Use 60 characters or fewer")
      |> unique_constraint(:token_hash)

    {token, changeset}
  end

  def hash(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  @doc """
  The live token with this value, with its team and user: not revoked, on a team with
  MCP on. Nil otherwise. The caller still checks the user passes the D4H bar.
  """
  def get_live(token) when is_binary(token) do
    MCPToken
    |> join(:inner, [t], team in assoc(t, :team))
    |> where([t, team], t.token_hash == ^hash(token) and is_nil(t.revoked_at))
    |> where([t, team], team.mcp_enabled)
    |> preload([t, team], [:user, team: team])
    |> Repo.one()
  end

  @doc "The team's tokens that aren't revoked, newest first, with their users."
  def get_live_for_team(%Team{} = team) do
    team.id
    |> live_for_team_query()
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "A live token on the team, by id, or nil. Never by a bare id from the page."
  def find_live(%Team{} = team, id) do
    team.id |> live_for_team_query() |> where([t], t.id == ^id) |> Repo.one()
  end

  def count_live_by_team do
    MCPToken
    |> where([t], is_nil(t.revoked_at))
    |> group_by([t], t.team_id)
    |> select([t], {t.team_id, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  def revoke!(%MCPToken{} = token, now) do
    token |> change(revoked_at: now) |> Repo.update!()
  end

  @doc "Revokes every live token on the team. Returns how many."
  def revoke_all!(%Team{} = team, now) do
    {count, _} = team.id |> live_for_team_query() |> Repo.update_all(set: [revoked_at: now])
    count
  end

  @doc "Records a use, at most once a minute, so a busy agent doesn't write every call."
  def touch!(%MCPToken{last_used_at: last} = token, now) do
    if is_nil(last) or DateTime.diff(now, last) >= 60,
      do: token |> change(last_used_at: now) |> Repo.update!(),
      else: token
  end

  defp live_for_team_query(team_id) do
    where(MCPToken, [t], t.team_id == ^team_id and is_nil(t.revoked_at))
  end
end

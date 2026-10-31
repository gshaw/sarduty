defmodule App.Model.AgentConnection do
  use App, :model

  alias App.Accounts.User
  alias App.Model.AgentClient
  alias App.Model.AgentConnection
  alias App.Model.Team
  alias App.Repo

  # An AI agent a team admin allowed on a team (#761), one row per agent. Allow writes the
  # row with a code; the agent trades the code for a refresh token and an access token,
  # and later trades the refresh token for a new pair. The database keeps only SHA-256
  # hashes: 32 random bytes need no keyed hash, unlike a login code. The prefixes let
  # secret scanners spot a leaked token. Revoked rows stay, so the call log and events
  # still say who.

  @access_prefix "sarduty_at_"
  @refresh_prefix "sarduty_rt_"
  @rand_size 32
  @prune_pending_after_days 1

  schema "agent_connections" do
    belongs_to :team, Team
    belongs_to :user, User
    belongs_to :agent_client, AgentClient
    field :name, :string
    field :redirect_uri, :string
    field :code_hash, :binary, redact: true
    field :code_challenge, :string, redact: true
    field :code_expires_at, :utc_datetime_usec
    field :refresh_token_hash, :binary, redact: true
    field :previous_refresh_token_hash, :binary, redact: true
    field :previous_refresh_expires_at, :utc_datetime_usec
    field :refreshed_at, :utc_datetime_usec
    field :access_token_hash, :binary, redact: true
    field :access_expires_at, :utc_datetime_usec
    field :connected_at, :utc_datetime_usec
    field :last_used_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def hash(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  @doc "A new code, access token, or refresh token: random, url-safe."
  def new_secret(:code), do: random()
  def new_secret(:access), do: @access_prefix <> random()
  def new_secret(:refresh), do: @refresh_prefix <> random()

  defp random, do: @rand_size |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc """
  The live connection with this access token, with its team and user: not revoked, not
  expired, on a team with Agents on. Nil otherwise. The caller still checks the user
  passes the D4H bar.
  """
  def get_by_access_token(token, now) when is_binary(token) do
    AgentConnection
    |> join(:inner, [c], team in assoc(c, :team))
    |> where([c], c.access_token_hash == ^hash(token) and is_nil(c.revoked_at))
    |> where([c], c.access_expires_at > ^now)
    |> where([c, team], team.mcp_enabled)
    |> preload([c, team], [:user, team: team])
    |> Repo.one()
  end

  @doc "The unrevoked connection on the team holding this code, or nil."
  def get_by_code(%Team{} = team, code) when is_binary(code) do
    team.id |> live_for_team_query() |> where([c], c.code_hash == ^hash(code)) |> Repo.one()
  end

  def get_by_code(_team, _code), do: nil

  @doc """
  The unrevoked connection on the team whose refresh token, or the one it just replaced,
  is this one, or nil.
  """
  def get_by_refresh_token(%Team{} = team, token) when is_binary(token) do
    hash = hash(token)

    team.id
    |> live_for_team_query()
    |> where([c], c.refresh_token_hash == ^hash or c.previous_refresh_token_hash == ^hash)
    |> Repo.one()
  end

  def get_by_refresh_token(_team, _token), do: nil

  @doc "The team's connected agents, newest first, with their users."
  def get_connected_for_team(%Team{} = team) do
    team.id
    |> live_for_team_query()
    |> where([c], not is_nil(c.connected_at))
    |> order_by([c], desc: c.connected_at, desc: c.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "A connected agent on the team, by id, or nil. Never by a bare id from the page."
  def find_connected(%Team{} = team, id) do
    team.id
    |> live_for_team_query()
    |> where([c], c.id == ^id and not is_nil(c.connected_at))
    |> Repo.one()
  end

  def count_connected_by_team do
    AgentConnection
    |> where([c], is_nil(c.revoked_at) and not is_nil(c.connected_at))
    |> group_by([c], c.team_id)
    |> select([c], {c.team_id, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  def revoke!(%AgentConnection{} = connection, now) do
    connection |> change(revoked_at: now) |> Repo.update!()
  end

  @doc "Revokes every connection on the team. Returns how many were connected."
  def revoke_all!(%Team{} = team, now) do
    {_all, connected_ats} =
      team.id
      |> live_for_team_query()
      |> select([c], c.connected_at)
      |> Repo.update_all(set: [revoked_at: now])

    Enum.count(connected_ats, &(&1 != nil))
  end

  @doc "Records a use, at most once a minute, so a busy agent doesn't write every call."
  def touch!(%AgentConnection{last_used_at: last} = connection, now) do
    if is_nil(last) or DateTime.diff(now, last) >= 60,
      do: connection |> change(last_used_at: now) |> Repo.update!(),
      else: connection
  end

  @doc """
  Deletes rows from an Allow whose code was never traded, over a day old. They never
  connected, so nothing points at them. Returns how many.
  """
  def prune_pending(now) do
    cutoff = DateTime.add(now, -@prune_pending_after_days, :day)

    {count, _} =
      AgentConnection
      |> where([c], is_nil(c.connected_at) and c.inserted_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  defp live_for_team_query(team_id) do
    where(AgentConnection, [c], c.team_id == ^team_id and is_nil(c.revoked_at))
  end
end

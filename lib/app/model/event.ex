defmodule App.Model.Event do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Team
  alias App.Repo
  alias Plug.Crypto.KeyGenerator

  # Days each kind is kept. App.Worker.PruneEventsWorker deletes older ones each night.
  # Login events carry IPs, which are personal data, so they go after 90 days. Changes to
  # who can reach a team, MCP tokens included, are kept two years, as a record.
  @retention_days %{
    d4h_sync_round: 90,
    d4h_refresh_run: 90,
    d4h_team_sync: 90,
    d4h_team_refresh: 90,
    d4h_rate_limited: 90,
    login_code_requested: 90,
    login_code_limited: 90,
    login_code_missed: 90,
    login_blocked: 90,
    logged_in: 90,
    logged_out: 90,
    verify_limit_reached: 90,
    team_signup_failed: 90,
    team_signed_up: 730,
    team_key_changed: 730,
    login_grant_added: 730,
    login_grant_removed: 730,
    tax_credit_letters_sent: 730,
    mcp_turned_on: 730,
    mcp_turned_off: 730,
    mcp_token_created: 730,
    mcp_token_revoked: 730
  }

  @kinds Map.keys(@retention_days)

  # Something the app did, kept to answer questions later: how long sync rounds take,
  # which team failed and since when, who is guessing login codes. `data` holds counts
  # and ids, never names, emails, or phone numbers: a typed email or number is stored as
  # `who`, a keyed hash (who/1), so attempts on one account group
  # together. Healthchecks and Honeybadger alert; this table only records.
  schema "events" do
    field :kind, Ecto.Enum, values: @kinds
    belongs_to :team, Team
    belongs_to :user, User
    field :ip, :string
    field :user_agent, :string
    field :duration_ms, :integer
    field :data, :map, default: %{}
    field :occurred_at, :utc_datetime_usec
  end

  def kinds, do: @kinds

  @doc """
  Records an event. `attrs` takes `team_id`, `user_id`, `ip`, `user_agent`,
  `duration_ms`, `data`, and `occurred_at`, which defaults to now.
  """
  def record!(kind, attrs \\ []) when kind in @kinds do
    attrs = Map.new(attrs)

    Repo.insert!(%Event{
      kind: kind,
      team_id: attrs[:team_id],
      user_id: attrs[:user_id],
      ip: attrs[:ip],
      user_agent: attrs[:user_agent] && String.slice(attrs[:user_agent], 0, 255),
      duration_ms: attrs[:duration_ms],
      data: attrs[:data] || %{},
      occurred_at: attrs[:occurred_at] || DateTime.utc_now()
    })
  end

  @doc "Milliseconds from `started_at` to `now`."
  def duration_ms(started_at, now), do: DateTime.diff(now, started_at, :millisecond)

  @doc "The newest events, newest first, of one kind, team, and IP when given."
  def get_recent(filter, limit) do
    Event
    |> scope(kind: filter[:kind])
    |> scope(team_id: filter[:team_id])
    |> scope(ip: filter[:ip])
    |> order_by([e], desc: e.occurred_at, desc: e.id)
    |> limit(^limit)
    |> preload(:team)
    |> Repo.all()
  end

  @doc "The newest event of a kind, or nil."
  def get_last(kind) when kind in @kinds do
    Event
    |> where([e], e.kind == ^kind)
    |> order_by([e], desc: e.occurred_at, desc: e.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "How many events of a kind since `since`, and how many of those match `data`."
  def count_since(kind, since, data \\ %{}) when kind in @kinds do
    Event
    |> where([e], e.kind == ^kind and e.occurred_at >= ^since)
    |> scope(data: data)
    |> Repo.aggregate(:count)
  end

  @doc "Deletes each kind's events older than its retention. Returns how many."
  def prune(now) do
    Enum.reduce(@retention_days, 0, fn {kind, days}, total ->
      cutoff = DateTime.add(now, -days, :day)

      {count, _} =
        Event
        |> where([e], e.kind == ^kind and e.occurred_at < ^cutoff)
        |> Repo.delete_all()

      total + count
    end)
  end

  @doc """
  The IPs with the most events of these kinds since `since`, most first, as
  `{ip, count}`.
  """
  def get_top_ips(kinds, since, limit) do
    Event
    |> where([e], e.kind in ^kinds and e.occurred_at >= ^since and not is_nil(e.ip))
    |> group_by([e], e.ip)
    |> select([e], {e.ip, count(e.id)})
    |> order_by([e], desc: count(e.id), asc: e.ip)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  A typed email or number as a keyed hash, so attempts on one account group together
  without storing the address of someone who may not even use SAR Duty. The key comes
  from the app's secret, so the hash can't be matched against a list of emails.
  """
  def who({:phone, e164}), do: hash("phone:" <> e164)
  def who(email) when is_binary(email), do: hash(email |> String.trim() |> String.downcase())

  # cspell:ignore hmac -- Erlang's :crypto.mac/4 name for a keyed hash.
  defp hash(value) do
    :hmac
    |> :crypto.mac(:sha256, key(), value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  # Derived once, since deriving takes a thousand rounds.
  defp key do
    case :persistent_term.get({__MODULE__, :key}, nil) do
      nil ->
        secret = Application.fetch_env!(:sarduty, Web.Endpoint)[:secret_key_base]
        key = KeyGenerator.generate(secret, "security event who")
        :persistent_term.put({__MODULE__, :key}, key)
        key

      key ->
        key
    end
  end

  defp scope(query, kind: nil), do: query
  defp scope(query, kind: kind), do: where(query, [e], e.kind == ^kind)
  defp scope(query, team_id: nil), do: query
  defp scope(query, team_id: team_id), do: where(query, [e], e.team_id == ^team_id)
  defp scope(query, ip: nil), do: query
  defp scope(query, ip: ip), do: where(query, [e], e.ip == ^ip)

  defp scope(query, data: data) do
    Enum.reduce(data, query, fn {key, value}, query ->
      where(query, [e], fragment("json_extract(?, ?)", e.data, ^"$.#{key}") == ^value)
    end)
  end
end

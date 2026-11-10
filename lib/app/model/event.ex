defmodule App.Model.Event do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Team
  alias App.RateLimit
  alias App.Repo
  alias Plug.Crypto.KeyGenerator

  # Days each kind is kept. App.Worker.PruneEventsWorker deletes older ones each night.
  # Login events carry IPs, which are personal data, so they go after 90 days. Changes to
  # who can reach a team or an organization, AI agents included, and team admins viewing
  # as a member are kept two years, as a record. The MCP token kinds are for events from
  # before agents connected with OAuth (#761).
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
    verify_alarm: 90,
    verify_guess_found: 90,
    team_signup_failed: 90,
    integration_tested: 90,
    demo_deleted: 90,
    letter_pdfs_saved: 90,
    team_signed_up: 730,
    team_deleted: 730,
    team_key_changed: 730,
    login_grant_added: 730,
    login_grant_removed: 730,
    tax_credit_letters_sent: 730,
    mcp_turned_on: 730,
    mcp_turned_off: 730,
    mcp_token_created: 730,
    mcp_token_revoked: 730,
    agent_connected: 730,
    agent_disconnected: 730,
    member_logins_turned_on: 730,
    member_logins_turned_off: 730,
    feature_turned_on: 730,
    feature_turned_off: 730,
    id_cards_turned_on: 730,
    id_cards_turned_off: 730,
    member_viewed_as: 730,
    member_fields_changed: 730,
    organization_admin_added: 730,
    organization_admin_removed: 730,
    organization_hours_tags_changed: 730,
    organization_team_added: 730,
    organization_team_removed: 730,
    form_saved: 730,
    form_turned_on: 730,
    form_turned_off: 730
  }

  @kinds Map.keys(@retention_days)

  # Something the app did, kept to answer questions later: how long sync rounds take,
  # which team failed and since when, who is guessing login codes. `data` holds counts
  # and ids, never names, emails, or phone numbers. A typed email or number is kept
  # twice: encrypted in `email_or_phone`, to show on the Events page, and as `who`, a keyed
  # hash (who/1) that groups attempts on one account and counts them for the limits. And
  # `ip_key` is the IP as the limits count it (App.RateLimit.ip_key/1, IPv6 by its /64).
  # Both are indexed with kind and time (#974), so counting one account's or one
  # connection's events in a window is one index range. Web.LoginLimit counts wrong codes
  # and texts from these rows (#975), looking back one day, so the table is more than a
  # record: login events stay 90 days. Healthchecks and Honeybadger alert.
  schema "events" do
    field :kind, Ecto.Enum, values: @kinds
    belongs_to :team, Team
    belongs_to :user, User
    field :who, :string
    field :email_or_phone, App.Field.EncryptedString, redact: true
    field :ip, :string
    field :ip_key, :string
    field :user_agent, :string
    field :duration_ms, :integer
    field :data, :map, default: %{}
    field :occurred_at, :utc_datetime_usec
  end

  def kinds, do: @kinds

  @doc """
  Records an event. `attrs` takes `team_id`, `user_id`, `email_or_phone` (an email, or
  `{:phone, e164}`), `ip`, `user_agent`, `duration_ms`, `data`, and `occurred_at`, which
  defaults to now. `who` comes from `email_or_phone`, and `ip_key` from `ip`.
  """
  def record!(kind, attrs \\ []) when kind in @kinds do
    attrs = Map.new(attrs)

    Repo.insert!(%Event{
      kind: kind,
      team_id: attrs[:team_id],
      user_id: attrs[:user_id],
      who: attrs[:email_or_phone] && who(attrs[:email_or_phone]),
      email_or_phone: attrs[:email_or_phone] && shown(attrs[:email_or_phone]),
      ip: attrs[:ip],
      ip_key: attrs[:ip] && RateLimit.ip_key(attrs[:ip]),
      user_agent: attrs[:user_agent] && String.slice(attrs[:user_agent], 0, 255),
      duration_ms: attrs[:duration_ms],
      data: attrs[:data] || %{},
      occurred_at: attrs[:occurred_at] || DateTime.utc_now()
    })
  end

  @doc "Sets an integration test's outcome and how long it took, once it has an answer (#789)."
  def put_outcome!(%Event{} = event, outcome, duration_ms) do
    event
    |> Ecto.Changeset.change(
      data: Map.put(event.data, :outcome, outcome),
      duration_ms: duration_ms
    )
    |> Repo.update!()
  end

  @doc "Milliseconds from `started_at` to `now`."
  def duration_ms(started_at, now), do: DateTime.diff(now, started_at, :millisecond)

  @doc "The newest events, newest first, of one kind, team, `ip_key`, and `who` when given."
  def get_recent(filter, limit) do
    Event
    |> scope(kind: filter[:kind])
    |> scope(team_id: filter[:team_id])
    |> scope(ip_key: filter[:ip_key])
    |> scope(who: filter[:who])
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

  @doc """
  The newest event of a kind for each value of `data[key]`, as a map from that value to
  the event: the last test of each service on Adminland's Integrations page (#789).
  """
  def get_last_by(kind, key) when kind in @kinds do
    Event
    |> where([e], e.kind == ^kind)
    |> order_by([e], asc: e.occurred_at, asc: e.id)
    |> Repo.all()
    |> Map.new(&{&1.data[key], &1})
  end

  @doc """
  How many events of a kind since `since`. `opts` narrows them: `who:` and `ip_key:` to
  one account or connection, and `data:` to events whose `data` has these values.
  """
  def count_since(kind, since, opts \\ []) when kind in @kinds do
    Event
    |> where([e], e.kind == ^kind and e.occurred_at >= ^since)
    |> scope(who: opts[:who])
    |> scope(ip_key: opts[:ip_key])
    |> scope(data: opts[:data] || %{})
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
  `{ip_key, count}`. An IPv6 /64 counts as one, as the limits count it.
  """
  def get_top_ips(kinds, since, limit) do
    kinds
    |> top(since, limit)
    |> where([e], not is_nil(e.ip_key))
    |> group_by([e], e.ip_key)
    |> select([e], {e.ip_key, count(e.id)})
    |> order_by([e], asc: e.ip_key)
    |> Repo.all()
  end

  @doc """
  The accounts with the most events of these kinds since `since`, most first, as
  `{who, email_or_phone, count}`. `email_or_phone` is the latest one typed, or nil for
  an account with only events from before it was kept.
  """
  def get_top_accounts(kinds, since, limit) do
    top =
      kinds
      |> top(since, limit)
      |> where([e], not is_nil(e.who))
      |> group_by([e], e.who)
      |> select([e], {e.who, count(e.id)})
      |> order_by([e], asc: e.who)
      |> Repo.all()

    shown = top |> Enum.map(&elem(&1, 0)) |> get_shown()
    Enum.map(top, fn {who, count} -> {who, shown[who], count} end)
  end

  # The latest email or number typed for each hash. Each is encrypted with its own IV,
  # so SQL can't group them; the newest row per hash is enough.
  defp get_shown(hashes) do
    latest =
      from e in Event,
        where: e.who in ^hashes and not is_nil(e.email_or_phone),
        group_by: e.who,
        select: max(e.id)

    from(e in Event, where: e.id in subquery(latest), select: {e.who, e.email_or_phone})
    |> Repo.all()
    |> Map.new()
  end

  defp top(kinds, since, limit) do
    Event
    |> where([e], e.kind in ^kinds and e.occurred_at >= ^since)
    |> order_by([e], desc: count(e.id))
    |> limit(^limit)
  end

  @doc """
  A typed email or number as a keyed hash, so attempts on one account group together
  however it was typed, and the limits can count them by an indexed column. The key
  comes from the app's secret.
  """
  def who({:phone, e164}), do: hash("phone:" <> e164)
  def who(email) when is_binary(email), do: hash(email |> String.trim() |> String.downcase())

  # As typed, trimmed, so a list or a typo shows. Capped like an email address.
  defp shown({:phone, e164}), do: e164
  defp shown(email), do: email |> String.trim() |> String.slice(0, 254)

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
  defp scope(query, who: nil), do: query
  defp scope(query, who: who), do: where(query, [e], e.who == ^who)
  defp scope(query, ip_key: nil), do: query
  defp scope(query, ip_key: ip_key), do: where(query, [e], e.ip_key == ^ip_key)

  defp scope(query, data: data) do
    Enum.reduce(data, query, fn {key, value}, query ->
      where(query, [e], fragment("json_extract(?, ?)", e.data, ^"$.#{key}") == ^json(value))
    end)
  end

  # json_extract gives JSON's true and false as 1 and 0.
  defp json(true), do: 1
  defp json(false), do: 0
  defp json(value), do: value
end

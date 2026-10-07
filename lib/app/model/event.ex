defmodule App.Model.Event do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Team
  alias App.Repo

  # Days each kind is kept. App.Worker.PruneEventsWorker deletes older ones each night.
  @retention_days %{
    d4h_sync_round: 90,
    d4h_refresh_run: 90,
    d4h_team_sync: 90,
    d4h_team_refresh: 90,
    d4h_rate_limited: 90
  }

  @kinds Map.keys(@retention_days)

  # Something the app did, kept to answer questions later: how long sync rounds take,
  # which team failed and since when. `data` holds counts and ids, never names, emails,
  # or phone numbers. Healthchecks and Honeybadger alert; this table only records.
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

  @doc "The newest events, newest first, of one kind and one team when given."
  def get_recent(filter, limit) do
    Event
    |> scope(kind: filter[:kind])
    |> scope(team_id: filter[:team_id])
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

  defp scope(query, kind: nil), do: query
  defp scope(query, kind: kind), do: where(query, [e], e.kind == ^kind)
  defp scope(query, team_id: nil), do: query
  defp scope(query, team_id: team_id), do: where(query, [e], e.team_id == ^team_id)

  defp scope(query, data: data) do
    Enum.reduce(data, query, fn {key, value}, query ->
      where(query, [e], fragment("json_extract(?, ?)", e.data, ^"$.#{key}") == ^value)
    end)
  end
end

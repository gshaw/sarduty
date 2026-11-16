defmodule App.Model.AIAsk do
  @moduledoc """
  One AI writing ask (App.Operation.AskAI): who asked, on which team, for what, and what
  it cost. Adminland › AI writing sums these for this month's spend against the budget,
  and a team's asks today against the daily limit. A row is written as the ask starts,
  as stopped, and its tokens and cost as each request returns, so an ask stopped or cut
  off keeps what it spent; the end sets how it ended. An ask that never reached Claude, a
  limit or the budget, has no row.

  Kind `report` is an ask on the report editor, and `form` one on a team's Change form
  (#1089); both count toward the daily limit. Kind `history_line` is the line AI writes
  in a report's History after a save (App.Worker.WriteHistoryLineWorker): it counts
  toward the budget, never the daily limit, and Adminland counts it apart from asks.

  The ask's words can hold whatever a team admin typed, so they are redacted from error
  reports and cleared after 90 days; the numbers stay. Delete team deletes a team's asks.
  """
  use App, :model

  alias App.Accounts.User
  alias App.Model.AIAsk
  alias App.Model.Team
  alias App.Repo

  @outcomes [:used, :unchanged, :refused_by_checks, :refused, :failed, :stopped]
  @kinds [:report, :form, :history_line]
  @words_days 90

  # SAR Duty's own month and day, in BC, as Adminland's other times are.
  @timezone "America/Vancouver"

  schema "ai_asks" do
    belongs_to :team, Team
    belongs_to :user, User
    field :kind, Ecto.Enum, values: @kinds
    field :ask, :string, redact: true
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :cache_write_tokens, :integer, default: 0
    field :cache_read_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost_microdollars, :integer, default: 0
    field :turns, :integer, default: 0
    field :duration_ms, :integer
    field :outcome, Ecto.Enum, values: @outcomes
    field :asked_at, :utc_datetime_usec
  end

  def outcomes, do: @outcomes
  def timezone, do: @timezone

  @doc "Records an ask. `attrs` takes every field but the id."
  def record!(attrs), do: AIAsk |> struct!(Map.new(attrs)) |> Repo.insert!()

  @doc "Sets `attrs` on a recorded ask: its tokens and cost so far, or how it ended."
  def update!(%AIAsk{} = ask, attrs), do: ask |> change(attrs) |> Repo.update!()

  @doc "The start of `now`'s month in BC, in UTC."
  def month_start(now) do
    local = DateTime.shift_zone!(now, @timezone)
    start_of(local.year, local.month, 1)
  end

  @doc "The start of `now`'s day in BC, in UTC."
  def day_start(now) do
    local = DateTime.shift_zone!(now, @timezone)
    start_of(local.year, local.month, local.day)
  end

  defp start_of(year, month, day) do
    year
    |> Date.new!(month, day)
    |> DateTime.new!(~T[00:00:00], @timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  @doc "What this month's asks cost, every team, in millionths of a dollar."
  def month_cost_microdollars(now) do
    since = month_start(now)
    AIAsk |> where([a], a.asked_at >= ^since) |> Repo.aggregate(:sum, :cost_microdollars) || 0
  end

  @doc "How many asks `team` made today, BC time. History lines don't count."
  def count_today(%Team{id: team_id}, now) do
    since = day_start(now)

    AIAsk
    |> where([a], a.team_id == ^team_id and a.asked_at >= ^since and a.kind != ^:history_line)
    |> Repo.aggregate(:count)
  end

  @doc """
  This month's asks summed by team, then by person: `%{teams: rows, people: rows}`,
  each row with its asks, its History lines, tokens, and cost, costliest first. Tokens
  and cost cover both.
  """
  def month_summary(now) do
    since = month_start(now)
    base = where(AIAsk, [a], a.asked_at >= ^since)
    %{teams: costliest(by_team(base)), people: costliest(by_person(base))}
  end

  defp by_team(query) do
    query
    |> join(:inner, [a], t in assoc(a, :team))
    |> group_by([a, t], [t.id, t.name])
    |> select([a, t], %{id: t.id, name: t.name})
    |> sums()
  end

  defp by_person(query) do
    query
    |> join(:left, [a], u in assoc(a, :user))
    |> join(:inner, [a], t in assoc(a, :team))
    |> group_by([a, u, t], [u.id, u.email, t.name])
    |> select([a, u, t], %{id: u.id, email: u.email, team: t.name})
    |> sums()
  end

  defp costliest(query), do: query |> Repo.all() |> Enum.sort_by(&(-&1.cost))

  defp sums(query) do
    select_merge(query, [a], %{
      asks: sum(fragment("CASE WHEN ? = 'history_line' THEN 0 ELSE 1 END", a.kind)),
      history_lines: sum(fragment("CASE WHEN ? = 'history_line' THEN 1 ELSE 0 END", a.kind)),
      input: sum(a.input_tokens),
      cache_write: sum(a.cache_write_tokens),
      cache_read: sum(a.cache_read_tokens),
      output: sum(a.output_tokens),
      cost: sum(a.cost_microdollars)
    })
  end

  @doc "The newest asks, newest first, with team and user."
  def get_recent(limit) do
    AIAsk
    |> order_by([a], desc: a.asked_at, desc: a.id)
    |> limit(^limit)
    |> preload([:team, :user])
    |> Repo.all()
  end

  @doc "Clears the words of asks older than #{@words_days} days. Returns how many."
  def prune_words(now) do
    cutoff = DateTime.add(now, -@words_days, :day)

    {count, _} =
      AIAsk
      |> where([a], a.asked_at < ^cutoff and not is_nil(a.ask))
      |> Repo.update_all(set: [ask: nil])

    count
  end
end

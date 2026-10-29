defmodule App.Model.ChoreEvent do
  use App, :model

  alias App.Model.Activity
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
  alias App.Model.Team
  alias App.Repo

  # One D4H event for a chore category's accepted chores in one month (#341). One
  # category, since an event takes one hours tag; one month, so it stays in one tax year
  # and the month its chores were done. SAR Duty owns the event and rebuilds it from its
  # chores: `needs_send` once one changes, until a send records how it went. `send_note`
  # is what the last send could not do: an error to fix, or that D4H would not publish
  # it. The local copy of the activity arrives with the next refresh, by
  # `d4h_activity_id`.
  schema "chore_events" do
    belongs_to :team, Team
    belongs_to :chore_category, ChoreCategory
    has_many :chores, Chore
    # The first day of the month its chores were done in.
    field :month, :date
    field :d4h_activity_id, :integer
    field :needs_send, :boolean, default: false
    field :sent_at, :utc_datetime_usec
    field :send_note, :string, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  A new event for the team's chore category and month. It has changes to send until a
  send records how it went, so a send cut short leaves it to send again.
  """
  def create!(team_id, chore_category_id, %Date{} = month),
    do:
      Repo.insert!(%ChoreEvent{
        team_id: team_id,
        chore_category_id: chore_category_id,
        month: Date.beginning_of_month(month),
        needs_send: true
      })

  @doc """
  Puts each of the team's accepted chores on the event for its chore category and the
  month it was done, made when there is none, and takes every other chore off its event.
  Both events of a chore that moves have changes to send. Where a category has two
  events for a month, as after the move to monthly events, the older keeps the chores.
  No unique index stops two: the emptied one stays until a send takes its attendance off
  D4H, or its hours count twice. Run it in a transaction.
  """
  def place!(team_id) do
    moves = moves(team_id, month_events(team_id), placed_chores(team_id))

    for {id, _from, to} <- moves,
        do: Chore |> where([c], c.id == ^id) |> Repo.update_all(set: [chore_event_id: to])

    moves |> Enum.flat_map(fn {_id, from, to} -> [from, to] end) |> mark_for_send!()
  end

  # The team's events by chore category and month. Newest first, so the oldest event of a
  # month is the one left in the map.
  defp month_events(team_id) do
    ChoreEvent
    |> where([e], e.team_id == ^team_id)
    |> order_by([e], desc: e.id)
    |> select([e], {{e.chore_category_id, e.month}, e.id})
    |> Repo.all()
    |> Map.new()
  end

  # The chores that are on an event or should be.
  defp placed_chores(team_id) do
    Chore
    |> where([c], c.team_id == ^team_id)
    |> where([c], c.status == :accepted or not is_nil(c.chore_event_id))
    |> select([c], {c.id, c.status, c.chore_category_id, c.date, c.chore_event_id})
    |> Repo.all()
  end

  # `[{chore_id, from_event_id, to_event_id}]` for each chore not on the event it should
  # be on, making the events it needs.
  defp moves(team_id, events, chores) do
    {_events, moves} =
      Enum.reduce(chores, {events, []}, fn {id, status, category_id, date, event_id},
                                           {events, moves} ->
        {events, want} = target(team_id, events, status, category_id, date)
        if want == event_id, do: {events, moves}, else: {events, [{id, event_id, want} | moves]}
      end)

    moves
  end

  defp target(_team_id, events, status, _category_id, _date) when status != :accepted,
    do: {events, nil}

  defp target(team_id, events, :accepted, category_id, date) do
    key = {category_id, Date.beginning_of_month(date)}

    case events do
      %{^key => id} ->
        {events, id}

      _none ->
        %ChoreEvent{id: id} = create!(team_id, category_id, date)
        {Map.put(events, key, id), id}
    end
  end

  @doc "Marks the events with these ids as having changes to send."
  def mark_for_send!(ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    ChoreEvent
    |> where([e], e.id in ^ids)
    |> Repo.update_all(set: [needs_send: true, updated_at: DateTime.utc_now()])

    :ok
  end

  @doc """
  Records a send and the D4H event's id. `outcome` is `:sent`, `{:sent, note}` when it
  went but D4H would not publish it, or `{:failed, error}` to try again. A send that went
  clears `needs_send`, unless a chore changed while it ran (`updated_at` moved on).
  """
  def record_send!(%ChoreEvent{} = event, d4h_activity_id, outcome, now) do
    {status, note} = if outcome == :sent, do: {:sent, nil}, else: outcome
    set = [d4h_activity_id: d4h_activity_id, send_note: note, sent_at: now]

    {count, _rows} =
      ChoreEvent
      |> where([e], e.id == ^event.id and e.updated_at == ^event.updated_at)
      |> Repo.update_all(set: [needs_send: status == :failed, updated_at: now] ++ set)

    # A chore changed during the send: keep what the send learned, and leave its changes
    # to send.
    if count == 0 do
      ChoreEvent
      |> where([e], e.id == ^event.id)
      |> Repo.update_all(set: [{:needs_send, true} | set])
    end

    :ok
  end

  @doc """
  The team's chore activities (#575): one row per D4H activity, `%{d4h_activity_id:,
  minutes:}`, with the minutes of its accepted chores. An event emptied by declines
  counts 0.
  """
  def totals(team_id) do
    ChoreEvent
    |> where([e], e.team_id == ^team_id and not is_nil(e.d4h_activity_id))
    |> join(:left, [e], c in Chore, on: c.chore_event_id == e.id and c.status == :accepted)
    |> group_by([e], e.d4h_activity_id)
    |> select([e, c], %{d4h_activity_id: e.d4h_activity_id, minutes: coalesce(sum(c.minutes), 0)})
  end

  @doc "The activity with `chore_minutes` set when it is one of the team's chore activities."
  def put_chore_minutes(%Activity{team_id: team_id, d4h_activity_id: d4h_id} = activity) do
    total = team_id |> totals() |> where([e], e.d4h_activity_id == ^d4h_id) |> Repo.one()
    %{activity | chore_minutes: total && total.minutes}
  end

  @doc "One of the team's events, with its chore category and tags."
  def find!(%Team{} = team, id) do
    ChoreEvent
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload(chore_category: [chore_category_tags: :tag])
  end

  @doc "The team's events with changes to send, oldest first, as `find!/2` loads them."
  def get_to_send(team_id) do
    ChoreEvent
    |> where([e], e.team_id == ^team_id and e.needs_send)
    |> order_by([e], asc: e.id)
    |> preload(chore_category: [chore_category_tags: :tag])
    |> Repo.all()
  end

  @doc "The event's chores, with their members."
  def chores(%ChoreEvent{} = event) do
    Chore
    |> where([c], c.team_id == ^event.team_id and c.chore_event_id == ^event.id)
    |> where([c], c.status == :accepted)
    |> preload(:member)
    |> Repo.all()
  end

  @doc "How many of the team's events have changes to send."
  def count_to_send(team_id) do
    ChoreEvent
    |> where([e], e.team_id == ^team_id and e.needs_send)
    |> Repo.aggregate(:count)
  end

  @doc "The local copy of the event's D4H activity, once a refresh has brought it."
  def local_activity(%ChoreEvent{d4h_activity_id: nil}), do: nil

  def local_activity(%ChoreEvent{} = event),
    do: Repo.get_by(Activity, team_id: event.team_id, d4h_activity_id: event.d4h_activity_id)

  @doc """
  The team's events with chores, or with changes to send, newest month first. Each comes
  with its last chore's date, members, minutes, and local activity once refreshed:
  `%{event:, date:, members:, minutes:, activity:}`. One left with no chores drops off
  once sent: D4H can't delete it, and an empty draft counts no hours.
  """
  def get_all_with_totals(team_id) do
    totals = chore_totals(team_id)

    for {event, activity} <- with_activities(team_id),
        event.needs_send or Map.has_key?(totals, event.id) do
      {date, members, minutes} = Map.get(totals, event.id, {nil, 0, 0})
      %{event: event, date: date, members: members, minutes: minutes, activity: activity}
    end
    |> Enum.sort_by(&newest_month_first/1)
  end

  defp newest_month_first(%{event: event}),
    do: {-Date.to_gregorian_days(event.month), event.chore_category.title, event.id}

  defp with_activities(team_id) do
    ChoreEvent
    |> where([e], e.team_id == ^team_id)
    |> join(:left, [e], a in Activity,
      on: a.team_id == e.team_id and a.d4h_activity_id == e.d4h_activity_id
    )
    |> preload(:chore_category)
    |> select([e, a], {e, a})
    |> Repo.all()
  end

  # Each event's last chore date, members, and minutes, by event id.
  defp chore_totals(team_id) do
    Chore
    |> where([c], c.team_id == ^team_id and c.status == :accepted)
    |> where([c], not is_nil(c.chore_event_id))
    |> group_by([c], c.chore_event_id)
    |> select(
      [c],
      {c.chore_event_id, {max(c.date), count(c.member_id, :distinct), sum(c.minutes)}}
    )
    |> Repo.all()
    |> Map.new()
  end
end

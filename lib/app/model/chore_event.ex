defmodule App.Model.ChoreEvent do
  use App, :model

  alias App.Model.Activity
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
  alias App.Model.Team
  alias App.Repo

  # One D4H event per month and chore category (#341). SAR Duty owns it and rebuilds it
  # from the accepted chores whenever one of them changes: `needs_send` until the nightly
  # send goes through. `send_error` is the last send's trouble, if any. The local copy of
  # the activity arrives with the next refresh, found by `d4h_activity_id`.
  schema "chore_events" do
    belongs_to :team, Team
    belongs_to :chore_category, ChoreCategory
    has_many :chores, Chore
    field :month, :date
    field :d4h_activity_id, :integer
    field :needs_send, :boolean, default: false
    field :sent_at, :utc_datetime_usec
    field :send_error, :string
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The event for the team's category and month, made when it's the first."
  def find_or_create!(team_id, chore_category_id, %Date{} = date) do
    month = Date.beginning_of_month(date)
    attrs = [team_id: team_id, chore_category_id: chore_category_id, month: month]

    ChoreEvent
    |> struct(attrs)
    |> Repo.insert!(
      on_conflict: :nothing,
      conflict_target: [:team_id, :chore_category_id, :month]
    )

    Repo.get_by!(ChoreEvent, attrs)
  end

  @doc "Marks the events with these ids for the next send."
  def mark_for_send!(ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()
    now = DateTime.utc_now()

    ChoreEvent
    |> where([e], e.id in ^ids)
    |> Repo.update_all(set: [needs_send: true, updated_at: now])

    :ok
  end

  @doc """
  Records a send: the D4H event's id, and the trouble if any rows did not go. A clean
  send clears `needs_send`, unless a chore changed while it ran (`updated_at` moved on).
  """
  def record_send!(%ChoreEvent{} = event, d4h_activity_id, error, now) do
    needs_send = not is_nil(error)

    {count, _rows} =
      ChoreEvent
      |> where([e], e.id == ^event.id and e.updated_at == ^event.updated_at)
      |> Repo.update_all(
        set: [
          d4h_activity_id: d4h_activity_id,
          needs_send: needs_send,
          send_error: error,
          sent_at: now,
          updated_at: now
        ]
      )

    # A chore changed during the send: keep the id, and send again tonight.
    if count == 0 do
      ChoreEvent
      |> where([e], e.id == ^event.id)
      |> Repo.update_all(set: [d4h_activity_id: d4h_activity_id, sent_at: now])
    end

    :ok
  end

  @doc "The team's events that wait for a send, oldest month first."
  def get_to_send(team_id) do
    ChoreEvent
    |> where([e], e.team_id == ^team_id and e.needs_send)
    |> order_by([e], asc: e.month, asc: e.id)
    |> preload(chore_category: [chore_category_tags: :tag])
    |> Repo.all()
  end

  @doc "The event's accepted chores, with their members."
  def accepted_chores(%ChoreEvent{} = event) do
    Chore
    |> where([c], c.team_id == ^event.team_id and c.chore_event_id == ^event.id)
    |> where([c], c.status == :accepted)
    |> preload(:member)
    |> Repo.all()
  end

  @doc """
  The team's events, newest month first, each with its members, minutes, and local
  activity once refreshed: `%{event:, members:, minutes:, activity:}`. Events with no
  accepted chores and nothing in D4H are left out.
  """
  def get_all_with_totals(team_id) do
    totals = accepted_totals(team_id)

    team_id
    |> with_activities()
    |> Enum.map(fn {event, activity} ->
      {members, minutes} = Map.get(totals, event.id, {0, 0})
      %{event: event, members: members, minutes: minutes, activity: activity}
    end)
    |> Enum.reject(&(&1.members == 0 and is_nil(&1.event.d4h_activity_id)))
  end

  defp with_activities(team_id) do
    ChoreEvent
    |> where([e], e.team_id == ^team_id)
    |> join(:left, [e], a in Activity,
      on: a.team_id == e.team_id and a.d4h_activity_id == e.d4h_activity_id
    )
    |> order_by([e], desc: e.month, asc: e.chore_category_id)
    |> preload(:chore_category)
    |> select([e, a], {e, a})
    |> Repo.all()
  end

  # Each event's members and minutes, as event id to `{members, minutes}`.
  defp accepted_totals(team_id) do
    Chore
    |> where([c], c.team_id == ^team_id and c.status == :accepted)
    |> where([c], not is_nil(c.chore_event_id))
    |> group_by([c], c.chore_event_id)
    |> select([c], {c.chore_event_id, {count(c.member_id, :distinct), sum(c.minutes)}})
    |> Repo.all()
    |> Map.new()
  end
end

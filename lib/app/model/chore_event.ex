defmodule App.Model.ChoreEvent do
  use App, :model

  alias App.Model.Activity
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
  alias App.Model.Team
  alias App.Repo

  # One D4H event made by a team admin's send (#341): the sent chores of one chore
  # category and one year. One category, since an event takes one hours tag; one year,
  # since its date decides which tax credit letter counts the hours. SAR Duty owns the
  # event and rebuilds it from its chores: `needs_send` once a sent chore changes, until
  # a team admin sends the changes. `send_note` is what the last send could not do: an
  # error to fix, or that D4H would not publish it. `locked` once D4H has approved it:
  # SAR Duty cannot change it again. The local copy of the activity arrives with the
  # next refresh, by `d4h_activity_id`.
  schema "chore_events" do
    belongs_to :team, Team
    belongs_to :chore_category, ChoreCategory
    has_many :chores, Chore
    field :year, :integer
    field :d4h_activity_id, :integer
    field :needs_send, :boolean, default: false
    field :sent_at, :utc_datetime_usec
    field :send_note, :string
    field :locked, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  A new event for the team's chore category and year. It has changes to send until a
  send records how it went, so a send cut short leaves a Send changes button.
  """
  def create!(team_id, chore_category_id, year),
    do:
      Repo.insert!(%ChoreEvent{
        team_id: team_id,
        chore_category_id: chore_category_id,
        year: year,
        needs_send: true
      })

  @doc "Whether a chore still belongs on the event: accepted, same category, same year."
  def fits?(%ChoreEvent{} = event, %Chore{} = chore) do
    chore.status == :accepted and chore.chore_category_id == event.chore_category_id and
      chore.date.year == event.year
  end

  @doc "Marks the events with these ids as having changes to send."
  def mark_for_send!(ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    ChoreEvent
    |> where([e], e.id in ^ids and not e.locked)
    |> Repo.update_all(set: [needs_send: true, updated_at: DateTime.utc_now()])

    :ok
  end

  @doc """
  Records a send and the D4H event's id. `outcome` is `:sent`, `{:sent, note}` when it
  went but D4H would not publish it, `{:failed, error}` to try again, or `{:locked,
  note}` once D4H has approved it. A send that went clears `needs_send`, unless a chore
  changed while it ran (`updated_at` moved on).
  """
  def record_send!(%ChoreEvent{} = event, d4h_activity_id, outcome, now) do
    {status, note} = if outcome == :sent, do: {:sent, nil}, else: outcome

    {count, _rows} =
      ChoreEvent
      |> where([e], e.id == ^event.id and e.updated_at == ^event.updated_at)
      |> Repo.update_all(
        set: [
          d4h_activity_id: d4h_activity_id,
          needs_send: status == :failed,
          locked: status == :locked,
          send_note: note,
          sent_at: now,
          updated_at: now
        ]
      )

    # A chore changed during the send: keep what the send learned, and leave its changes
    # to send, unless D4H has approved the event.
    if count == 0 do
      ChoreEvent
      |> where([e], e.id == ^event.id)
      |> Repo.update_all(
        set: [
          d4h_activity_id: d4h_activity_id,
          needs_send: status != :locked,
          locked: status == :locked,
          send_note: note,
          sent_at: now
        ]
      )
    end

    :ok
  end

  @doc "One of the team's events, with its chore category and tags."
  def find!(%Team{} = team, id) do
    ChoreEvent
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload(chore_category: [chore_category_tags: :tag])
  end

  @doc "The event's chores, with their members."
  def chores(%ChoreEvent{} = event) do
    Chore
    |> where([c], c.team_id == ^event.team_id and c.chore_event_id == ^event.id)
    |> where([c], c.status == :accepted)
    |> preload(:member)
    |> Repo.all()
  end

  @doc "The D4H ids of the team's chore events."
  def d4h_activity_ids(team_id) do
    ChoreEvent
    |> where([e], e.team_id == ^team_id and not is_nil(e.d4h_activity_id))
    |> select([e], e.d4h_activity_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  The team's events, newest first, each with its last chore's date, members, minutes,
  and local activity once refreshed: `%{event:, date:, members:, minutes:, activity:}`.
  """
  def get_all_with_totals(team_id) do
    totals = chore_totals(team_id)

    team_id
    |> with_activities()
    |> Enum.map(fn {event, activity} ->
      {date, members, minutes} = Map.get(totals, event.id, {nil, 0, 0})
      %{event: event, date: date, members: members, minutes: minutes, activity: activity}
    end)
    |> Enum.sort_by(
      &{&1.event.year, &1.date && Date.to_gregorian_days(&1.date), &1.event.id},
      :desc
    )
  end

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

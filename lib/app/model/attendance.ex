defmodule App.Model.Attendance do
  use App, :model

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  schema "attendances" do
    belongs_to :member, Member
    belongs_to :activity, Activity
    field :d4h_attendance_id, :integer
    field :duration_in_minutes, :integer
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :status, :string
    # When the member replied to the invitation (#444), for the Replied column and New.
    # Nil until they reply, and on rows from before replies.
    field :replied_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Attendance{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :member_id,
      :activity_id,
      :d4h_attendance_id,
      :duration_in_minutes,
      :started_at,
      :finished_at,
      :status,
      :replied_at
    ])
    |> validate_required([
      :member_id,
      :activity_id,
      :d4h_attendance_id,
      :duration_in_minutes,
      :status
    ])
  end

  # def get(id), do: Repo.get(Attendance, id)
  # def get!(id), do: Repo.get!(Attendance, id)
  def get_by(params), do: Repo.get_by(Attendance, params)

  def insert!(params) do
    changeset = Attendance.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%Attendance{} = record, params) do
    changeset = Attendance.build_changeset(record, params)
    Repo.update!(changeset)
  end

  # def delete(%Attendance{} = record), do: Repo.delete(record)

  @doc """
  One row per member per activity. D4H allows two rows for one member on an activity
  (#519), so every list, count, and reply starts here. The row with a reply wins:
  attending, then absent, then any other status, then requested; the oldest on a tie.
  Keeps the order of each member's first row.
  """
  def one_per_member(rows) do
    best =
      rows |> Enum.group_by(&key/1) |> Map.new(fn {k, rs} -> {k, Enum.min_by(rs, &rank/1)} end)

    rows |> Enum.map(&key/1) |> Enum.uniq() |> Enum.map(&Map.fetch!(best, &1))
  end

  defp key(row), do: {row.activity_id, row.member_id}
  defp rank(row), do: {status_rank(row.status), row.id}

  defp status_rank("attending"), do: 0
  defp status_rank("absent"), do: 1
  defp status_rank("requested"), do: 3
  defp status_rank(_status), do: 2

  @doc """
  The member's row on the activity, their invitation (#444), or nil when they aren't
  invited. Both must be the activity's team's. The row `one_per_member/1` picks, so a
  reply changes the row the activity's page shows.
  """
  def invitation(%Activity{} = activity, %Member{} = member) do
    Attendance
    |> join(:inner, [r], m in assoc(r, :member))
    |> where([r, m], r.activity_id == ^activity.id and r.member_id == ^member.id)
    |> where([r, m], m.team_id == ^activity.team_id and m.team_id == ^member.team_id)
    |> Repo.all()
    |> one_per_member()
    |> List.first()
  end

  @doc """
  The member's invitations to these activities, as `%{activity_id => attendance}`: the
  row of each `invitation/2` picks.
  """
  def invitations(%Member{} = member, activity_ids) do
    Attendance
    |> join(:inner, [r], m in assoc(r, :member))
    |> where([r, m], r.activity_id in ^activity_ids and r.member_id == ^member.id)
    |> where([r, m], m.team_id == ^member.team_id)
    |> Repo.all()
    |> one_per_member()
    |> Map.new(&{&1.activity_id, &1})
  end

  @doc """
  How each activity's invited members stand, by D4H status, as `%{activity_id =>
  %{attending: n, absent: n, requested: n}}`. On an activity's own panel, attending
  reads "signed up" before the start and "attended" from it. Only the team's members'
  rows count, each member once (`one_per_member/1`); every id gets a map, zeros included.
  """
  def reply_counts(%Team{} = team, activity_ids) do
    Attendance
    |> join(:inner, [r], m in assoc(r, :member))
    |> where([r, m], r.activity_id in ^activity_ids and m.team_id == ^team.id)
    |> select([r], map(r, [:id, :activity_id, :member_id, :status]))
    |> Repo.all()
    |> count_replies(activity_ids)
  end

  @doc "`reply_counts/2` from the activities' rows: each member once, by status."
  def count_replies(rows, activity_ids) do
    zero = %{attending: 0, absent: 0, requested: 0}

    rows
    |> one_per_member()
    |> Enum.filter(&(&1.status in ["attending", "absent", "requested"]))
    |> Enum.reduce(Map.new(activity_ids, &{&1, zero}), fn row, counts ->
      Map.update!(
        counts,
        row.activity_id,
        &Map.update!(&1, status_key(row.status), fn n -> n + 1 end)
      )
    end)
  end

  defp status_key("attending"), do: :attending
  defp status_key("absent"), do: :absent
  defp status_key("requested"), do: :requested

  @doc """
  When the member replied, for a row the refresh saves over `old` with D4H's `status`,
  changed in D4H at `changed_at`. A move to attending or absent before the activity's
  start `starts_at` is a reply then. A move back to requested clears it. Anything else
  keeps the old time: a change after the start is the door's, not a reply. A new row has
  none, since the refresh never saw it change.
  """
  def replied_at(nil, _status, _changed_at, _starts_at), do: nil

  def replied_at(%Attendance{status: status} = old, status, _changed_at, _starts_at),
    do: old.replied_at

  def replied_at(%Attendance{}, "requested", _changed_at, _starts_at), do: nil

  def replied_at(%Attendance{} = old, _status, %DateTime{} = changed_at, starts_at) do
    if DateTime.before?(changed_at, starts_at),
      do: DateTime.truncate(changed_at, :second),
      else: old.replied_at
  end

  @doc """
  The members D4H shows as signed up (attending) for the activity. Not requested: D4H
  gives every invited member a requested row until they reply.
  """
  def signed_up_members(%Activity{} = activity) do
    Member
    |> join(:inner, [m], a in Attendance, on: a.member_id == m.id)
    |> where([m, a], a.activity_id == ^activity.id and a.status == "attending")
    |> where([m], m.team_id == ^activity.team_id)
    |> distinct(true)
    |> Repo.all()
  end

  @doc """
  Attended rows: attending, on an activity not deleted, and started by `now`. This is
  what attended means everywhere; every count, hours total, year list, and last
  attended starts here. D4H marks a sign-up for a coming activity attending too, so
  `status == "attending"` alone is not attended (#364). Joins the activity as
  `:activity`.
  """
  def attended(query \\ Attendance, %DateTime{} = now),
    do: query |> attending() |> where([r], r.started_at <= ^now)

  @doc "Sign-ups for coming activities: attending rows that start after `now`."
  def signed_up(query \\ Attendance, %DateTime{} = now),
    do: query |> attending() |> where([r], r.started_at > ^now)

  defp attending(query) do
    query
    |> join_activity()
    |> where([r], r.status == "attending")
    |> where([activity: a], is_nil(a.deleted_at))
  end

  defp join_activity(query) do
    if has_named_binding?(query, :activity),
      do: query,
      else: join(query, :inner, [r], a in assoc(r, :activity), as: :activity)
  end

  @doc "Rows that started in a year or rolling period in `timezone` (Service.Period.bounds/3)."
  def started_in(query, period, timezone, now \\ DateTime.utc_now()) do
    {start, finish} = Service.Period.bounds(period, timezone, now)

    query
    |> where([r], r.started_at >= ^start)
    |> where([r], r.started_at < ^finish)
  end

  @doc """
  Attendance at the team's activities that carry the tag titled `title`, or all of it
  when `title` is blank.
  """
  def at_tagged(query, _team, title) when title in [nil, ""], do: query

  def at_tagged(query, team, title) do
    activities =
      Activity
      |> where([a], a.team_id == ^team.id)
      |> Activity.tagged(title)
      |> select([a], a.id)

    where(query, [at], at.activity_id in subquery(activities))
  end

  @doc "The years `query`'s rows span, newest first, in `timezone`."
  def years(query, timezone) do
    {first, last} =
      query
      |> select([r], {min(r.started_at), max(r.started_at)})
      |> Repo.one()

    Service.YearRange.years(first, last, timezone)
  end
end

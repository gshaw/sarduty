defmodule App.Model.Attendance do
  use App, :model

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
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
  The member's row on the activity, their invitation (#444), or nil when they aren't
  invited. Both must be the activity's team's. D4H allows two rows for one member; the
  first is the one replies change.
  """
  def invitation(%Activity{} = activity, %Member{} = member) do
    Attendance
    |> join(:inner, [r], m in assoc(r, :member))
    |> where([r, m], r.activity_id == ^activity.id and r.member_id == ^member.id)
    |> where([r, m], m.team_id == ^activity.team_id and m.team_id == ^member.team_id)
    |> order_by([r], asc: r.id)
    |> limit(1)
    |> Repo.one()
  end

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

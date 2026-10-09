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
      :status
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

  def scope(q, member_id: member_id) do
    q
    |> where([r], r.member_id == ^member_id)
    |> where([r], r.status == "attending")
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

  @doc "Rows that started in `year` in `timezone`."
  def started_in(query, year, timezone) do
    {start, finish} = Service.YearRange.bounds(year, timezone)

    query
    |> where([r], r.started_at >= type(^start, :naive_datetime))
    |> where([r], r.started_at < type(^finish, :naive_datetime))
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

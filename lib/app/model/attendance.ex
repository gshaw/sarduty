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

  def scope(q, member_id: member_id), do: where(q, [r], r.member_id == ^member_id)

  def tagged_hours_summary(year, tags) do
    from(
      at in Attendance,
      join: ac in assoc(at, :activity),
      where: fragment("strftime('%Y', ?) = ?", at.started_at, ^Integer.to_string(year)),
      where: ac.id in subquery(tagged_activity_ids(tags)),
      group_by: at.member_id,
      select: %{
        member_id: at.member_id,
        count: count(at.id),
        hours: fragment("cast(round(? + 0.5) as int)", sum(at.duration_in_minutes) / 60.0)
      }
    )
  end

  defp tagged_activity_ids(tags) do
    subquery = select(Activity, [:id])
    Enum.reduce(tags, subquery, fn tag, sq -> or_where(sq, [ac], ^tag in ac.tags) end)
  end
end

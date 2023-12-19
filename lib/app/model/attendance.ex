defmodule App.Model.Attendance do
  use App, :model

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
end

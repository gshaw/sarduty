defmodule App.Model.Activity do
  use App, :model

  import Ecto.Query

  alias App.Field.TrimmedString
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Team
  alias App.Repo
  alias App.Validate

  def primary_hours_tag, do: "Primary Hours"
  def secondary_hours_tag, do: "Secondary Hours"

  schema "activities" do
    belongs_to :team, Team
    has_many :attendances, Attendance, where: [status: "attending"]
    has_many :members, through: [:attendances, :member]
    field :d4h_activity_id, :integer
    field :ref_id, :string
    field :tracking_number, :string
    field :is_published, :boolean
    field :title, TrimmedString
    field :description, TrimmedString
    field :address, TrimmedString
    field :coordinate, :string
    field :activity_kind, :string
    field :hours_kind, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :tags, {:array, :string}
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%Activity{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :team_id,
      :d4h_activity_id,
      :ref_id,
      :tracking_number,
      :is_published,
      :title,
      :description,
      :address,
      :coordinate,
      :activity_kind,
      :hours_kind,
      :started_at,
      :finished_at,
      :tags
    ])
    |> validate_required([
      :team_id,
      :d4h_activity_id,
      :is_published,
      :title,
      :activity_kind,
      :started_at,
      :finished_at
    ])
    |> Validate.name(:title)
    |> Validate.address(:address)
  end

  def get_all(team_id) do
    Activity
    |> where([r], r.team_id == ^team_id)
    |> order_by([r], desc: r.started_at)
    |> Repo.all()
  end

  def get(id), do: Repo.get(Activity, id)
  # def get!(id), do: Repo.get!(Activity, id)

  def scope(q, team_id: team_id), do: where(q, team_id: ^team_id)

  def get_by(params), do: Repo.get_by(Activity, params)

  def insert!(params) do
    changeset = Activity.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%Activity{} = record, params) do
    changeset = Activity.build_changeset(record, params)
    Repo.update!(changeset)
  end
end

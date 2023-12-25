defmodule App.Model.Activity do
  use App, :model

  import Ecto.Query

  alias App.Field.TrimmedString
  alias App.Model.Activity
  alias App.Model.Team
  alias App.Repo
  alias App.Validate

  schema "activities" do
    belongs_to :team, Team
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

  # q = query
  # r = record

  def get(id), do: Repo.get(Activity, id)
  # def get!(id), do: Repo.get!(Activity, id)

  def scope(q, team_id: team_id), do: where(q, team_id: ^team_id)

  def scope(q, q: nil), do: q
  def scope(q, q: ""), do: q

  def scope(q, q: search_filter) do
    # https://dev.to/ivor/beware-ectos-orwhere-pitfall-50bb
    subquery =
      Activity
      |> where([r], like(r.title, ^"%#{search_filter}%"))
      |> or_where([r], like(r.ref_id, ^"%#{search_filter}%"))
      |> or_where([r], like(r.tracking_number, ^"%#{search_filter}%"))
      |> or_where([r], like(r.tags, ^"%#{search_filter}%"))
      |> or_where([r], like(r.description, ^"%#{search_filter}%"))
      |> select([:id])

    where(q, [r], r.id in subquery(subquery))
  end

  def scope(q, date: "all"), do: q
  def scope(q, date: "past"), do: where(q, [r], r.started_at <= ^DateTime.utc_now())
  def scope(q, date: "future"), do: where(q, [r], r.started_at >= ^DateTime.utc_now())

  def scope(q, activity: "all"), do: q
  def scope(q, activity: activity), do: where(q, [r], r.activity_kind == ^activity)

  def scope(q, order: "date:desc"), do: order_by(q, [r], desc: r.started_at)
  def scope(q, order: "date:asc"), do: order_by(q, [r], asc: r.started_at)
  def scope(q, order: "id:desc"), do: order_by(q, [r], desc: r.ref_id)
  def scope(q, order: "id:asc"), do: order_by(q, [r], asc: r.ref_id)

  def get_by(params), do: Repo.get_by(Activity, params)

  def insert!(params) do
    changeset = Activity.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%Activity{} = record, params) do
    changeset = Activity.build_changeset(record, params)
    Repo.update!(changeset)
  end

  # def delete(%Activity{} = record), do: Repo.delete(record)
end

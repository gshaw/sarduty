defmodule App.Hosted.Activity do
  use App, :model

  @kinds ~w(event exercise incident)

  # An event, exercise, or incident. One table, so the three kinds share an id space as
  # in D4H. A deleted activity keeps its row with deleted_at set, and the API leaves it
  # out, as D4H does.
  schema "hosted_activities" do
    field :hosted_team_id, :integer
    field :kind, :string
    field :reference, :string
    field :title, :string
    field :description, :string
    field :tracking_number, :string
    field :published, :boolean, default: false
    field :street, :string
    field :town, :string
    field :region, :string
    field :country, :string
    field :lat, :float
    field :lng, :float
    field :tag_ids, {:array, :integer}, default: []
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :deleted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: @kinds

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [
      :reference,
      :title,
      :description,
      :tracking_number,
      :published,
      :street,
      :town,
      :region,
      :country,
      :lat,
      :lng,
      :tag_ids,
      :starts_at,
      :ends_at
    ])
    |> validate_required([:starts_at, :ends_at])
    |> validate_length(:reference, max: 30)
    |> validate_length(:title, max: 100)
    |> validate_length(:tracking_number, max: 50)
    |> validate_length(:street, max: 100)
    |> validate_length(:town, max: 100)
    |> validate_length(:region, max: 100)
    |> validate_length(:country, max: 100)
    |> validate_number(:lat, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:lng, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_ends_after_starts()
  end

  def validate_ends_after_starts(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.before?(ends_at, starts_at),
      do: add_error(changeset, :ends_at, "must be after the start"),
      else: changeset
  end
end

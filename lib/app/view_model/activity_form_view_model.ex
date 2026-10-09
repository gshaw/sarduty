defmodule App.ViewModel.ActivityFormViewModel do
  use App, :view_model

  alias App.Field
  alias App.Model.Activity
  alias App.Validate

  @kinds [{"Exercise", "exercise"}, {"Incident", "incident"}, {"Event", "event"}]
  @hours [{"Primary", "primary"}, {"Secondary", "secondary"}, {"Neither", "none"}]

  # Adding or changing a hosted team's activity. Times are on the team's wall clock.
  @primary_key false
  embedded_schema do
    field :kind, :string, default: "exercise"
    field :title, Field.TrimmedString
    field :description, Field.TrimmedString
    field :place, Field.TrimmedString
    field :tracking_number, Field.TrimmedString
    field :starts_at, :naive_datetime
    field :ends_at, :naive_datetime
    field :hours, :string, default: "primary"
    field :published, :boolean, default: false
  end

  @fields [:kind, :title, :starts_at, :ends_at, :place, :hours, :tracking_number, :description]

  def kinds, do: @kinds
  def hours, do: @hours

  def from_activity(nil, _timezone), do: %__MODULE__{}

  def from_activity(%Activity{} = activity, timezone) do
    %__MODULE__{
      kind: activity.activity_kind,
      title: activity.title,
      description: activity.description,
      place: activity.address,
      tracking_number: activity.tracking_number,
      starts_at: local(activity.started_at, timezone),
      ends_at: local(activity.finished_at, timezone),
      hours: hours_of(activity.tags || []),
      published: activity.is_published == true
    }
  end

  defp hours_of(tags) do
    cond do
      Activity.primary_hours_tag() in tags -> "primary"
      Activity.secondary_hours_tag() in tags -> "secondary"
      true -> "none"
    end
  end

  defp local(nil, _timezone), do: nil

  defp local(datetime, timezone) do
    {date, time} = Service.Convert.utc_to_local(datetime, timezone)
    NaiveDateTime.new!(date, time)
  end

  def changeset(%__MODULE__{} = form, params \\ %{}) do
    form
    |> cast(params, [
      :kind,
      :title,
      :description,
      :place,
      :tracking_number,
      :starts_at,
      :ends_at,
      :hours,
      :published
    ])
    |> validate_required([:title], message: "Enter a title.")
    |> validate_required([:starts_at], message: "Enter when it starts.")
    |> validate_required([:ends_at], message: "Enter when it finishes.")
    |> validate_inclusion(:kind, Enum.map(@kinds, &elem(&1, 1)))
    |> validate_inclusion(:hours, Enum.map(@hours, &elem(&1, 1)))
    |> validate_length(:title, max: 100)
    |> validate_length(:place, max: 100)
    |> validate_length(:tracking_number, max: 50)
    |> validate_length(:description, max: 10_000)
    |> validate_ends_after_starts()
    |> Validate.in_field_order(@fields)
  end

  defp validate_ends_after_starts(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && NaiveDateTime.compare(ends_at, starts_at) != :gt,
      do: add_error(changeset, :ends_at, "Enter a finish after the start."),
      else: changeset
  end

  # :insert, not :validate, so a failed save shows the error summary.
  def validate(form, params), do: form |> changeset(params) |> apply_action(:insert)
end

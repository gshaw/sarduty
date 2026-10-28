defmodule App.ViewModel.ActivityFormViewModel do
  use App, :view_model

  alias App.Field
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Model.Team
  alias App.Validate

  @kinds [{"Exercise", "exercise"}, {"Incident", "incident"}, {"Event", "event"}]
  @hours [{"Primary", "primary"}, {"Secondary", "secondary"}, {"Neither", "none"}]

  # Adding or changing an activity. Times are on the team's wall clock. The description is
  # HTML, cleaned to what the editor makes (Service.DescriptionHTML).
  @primary_key false
  embedded_schema do
    field :kind, :string, default: "exercise"
    field :title, Field.TrimmedString
    field :description, Field.TrimmedString
    field :place, Field.TrimmedString
    # The place's pin, "lat,lng" as the sync stores it, or nil (#610).
    field :coordinate, :string
    field :tracking_number, Field.TrimmedString
    field :starts_at, :naive_datetime
    field :ends_at, :naive_datetime
    field :hours, :string, default: "primary"
    field :published, :boolean, default: false
    # D4H custom field values as the form holds them, by D4H field id (#681): text, or
    # option ids as strings. SaveActivity turns them into what D4H takes.
    field :custom, :map, default: %{}
  end

  @fields [:kind, :title, :starts_at, :ends_at, :place, :hours, :tracking_number, :description]

  def kinds, do: @kinds
  def hours, do: @hours

  @doc "The form for `activity`, or a blank one for nil. Times are on the team's wall clock."
  def from_activity(nil, _team), do: %__MODULE__{}

  def from_activity(%Activity{} = activity, %Team{timezone: timezone} = team) do
    %__MODULE__{
      kind: activity.activity_kind,
      title: activity.title,
      description: description(activity),
      place: activity.address,
      coordinate: coordinate(Activity.pin(activity)),
      tracking_number: activity.tracking_number,
      starts_at: local(activity.started_at, timezone),
      ends_at: local(activity.finished_at, timezone),
      hours: hours_of(activity.tags, Activity.hours_tags(team)),
      published: activity.is_published == true,
      custom: form_custom(activity.custom_values)
    }
  end

  @doc """
  Whether the form leaves the activity's description alone: one with things the editor
  can't hold, such as a table or an image.
  """
  def description_locked?(nil), do: false

  def description_locked?(%Activity{description: description}),
    do: !Service.DescriptionHTML.editable?(description)

  defp description(%Activity{description: description} = activity) do
    if description_locked?(activity),
      do: description,
      else: Service.DescriptionHTML.clean(description)
  end

  defp form_custom(nil), do: %{}

  defp form_custom(values) do
    Map.new(values, fn
      {id, list} when is_list(list) -> {id, Enum.map(list, &to_string/1)}
      {id, value} -> {id, value}
    end)
  end

  # As put_coordinate/1 writes it, so an untouched pin is unchanged.
  defp coordinate(text) do
    if pin = Coordinate.build(text), do: Coordinate.to_string(pin, 5)
  end

  defp hours_of(tags, hours_tags) do
    case Activity.counts_as(tags, hours_tags) do
      :primary -> "primary"
      :secondary -> "secondary"
      nil -> "none"
    end
  end

  defp local(nil, _timezone), do: nil

  # To the minute, as the form's inputs send it back, so an untouched time is unchanged.
  defp local(datetime, timezone) do
    {date, time} = Service.Convert.utc_to_local(datetime, timezone)
    NaiveDateTime.new!(date, %{time | second: 0})
  end

  def changeset(%__MODULE__{} = form, params \\ %{}) do
    form
    |> cast(params, [
      :kind,
      :title,
      :description,
      :place,
      :coordinate,
      :tracking_number,
      :starts_at,
      :ends_at,
      :hours,
      :published,
      :custom
    ])
    |> validate_required([:title], message: "Enter a title.")
    |> validate_required([:starts_at], message: "Enter when it starts.")
    |> validate_required([:ends_at], message: "Enter when it finishes.")
    |> validate_inclusion(:kind, Enum.map(@kinds, &elem(&1, 1)))
    |> validate_inclusion(:hours, Enum.map(@hours, &elem(&1, 1)))
    |> validate_length(:title, max: 100)
    |> validate_length(:place, max: 100)
    |> put_coordinate()
    |> validate_length(:tracking_number, max: 50)
    |> validate_length(:description, max: 10_000)
    |> validate_ends_after_starts()
    |> Validate.in_field_order(@fields)
  end

  # A pasted latitude and longitude is the pin. Otherwise the pin is the one picked, kept
  # in the stored form, or none.
  defp put_coordinate(changeset) do
    pasted = changeset |> get_field(:place) |> Coordinate.parse()
    pin = pasted || changeset |> get_field(:coordinate) |> Coordinate.build()
    put_change(changeset, :coordinate, pin && Coordinate.to_string(pin, 5))
  end

  # A finish at the start is fine: chore events last no time (#487), and D4H and Records
  # take them.
  defp validate_ends_after_starts(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && NaiveDateTime.before?(ends_at, starts_at),
      do: add_error(changeset, :ends_at, "Enter a finish after the start."),
      else: changeset
  end

  @doc """
  The form's values, or its errors, on save. `finished_by:` is the team's wall clock now,
  since D4H and Records publish only an activity that has happened.
  """
  # :insert, not :validate, so a failed save shows the error summary.
  def validate(form, params, opts \\ []) do
    form
    |> changeset(params)
    |> validate_finished_to_publish(opts[:finished_by])
    |> apply_action(:insert)
  end

  defp validate_finished_to_publish(changeset, nil), do: changeset

  defp validate_finished_to_publish(changeset, now) do
    ends_at = get_field(changeset, :ends_at)

    if (get_change(changeset, :published) == true and ends_at) &&
         NaiveDateTime.after?(ends_at, now),
       do: add_error(changeset, :published, "Publish it once it has finished."),
       else: changeset
  end
end

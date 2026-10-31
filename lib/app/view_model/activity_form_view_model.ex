defmodule App.ViewModel.ActivityFormViewModel do
  use App, :view_model

  alias App.Field
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Model.Team
  alias App.Model.Template
  alias App.Validate

  @kinds [{"Exercise", "exercise"}, {"Incident", "incident"}, {"Event", "event"}]
  @hours [{"Primary", "primary"}, {"Secondary", "secondary"}, {"Neither", "none"}]

  # Adding or changing an activity. Times are on the team's wall clock. The description is
  # HTML, cleaned to what the editor makes (Service.DescriptionHTML). Add activity can
  # start from a template (#747), which fills the form: template_params/3.
  @primary_key false
  embedded_schema do
    field :template_id, :integer
    field :kind, :string, default: "exercise"
    field :title, Field.TrimmedString
    field :description, Field.TrimmedString
    field :place, Field.TrimmedString
    # The place's pin, "lat,lng" as the sync stores it, or nil (#610).
    field :coordinate, :string
    field :tracking_number, Field.TrimmedString
    field :starts_at, :naive_datetime
    field :ends_at, :naive_datetime
    # How many signed up is enough, and full (#447): SAR Duty's own, never sent.
    field :enough_at, :integer
    field :full_at, :integer
    field :hours, :string, default: "primary"
    field :published, :boolean, default: false
  end

  @fields [
    :template_id,
    :kind,
    :title,
    :starts_at,
    :ends_at,
    :enough_at,
    :full_at,
    :place,
    :hours,
    :tracking_number,
    :description
  ]

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
      enough_at: activity.enough_at,
      full_at: activity.full_at,
      hours: hours_of(activity.tags, Activity.hours_tags(team)),
      published: activity.is_published == true
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

  # As Coordinate.put_pin/1 writes it, so an untouched pin is unchanged.
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

  @doc """
  The form's params from `template` on Add activity (#746, #747): its kind when it has
  one, its title or else its name, its tax credit hours, and each other detail it has,
  Enough at and Full at among them (#447).
  Its start time goes on `today`, and Finish is Start and its duration. Picking a
  template starts the form over, so nothing typed before is kept.
  """
  def template_params(%Template{} = template, %Date{} = today) do
    starts_at = template.start_time && NaiveDateTime.new!(today, template.start_time)

    %{
      "template_id" => Integer.to_string(template.id),
      "kind" => template.activity_kind,
      "title" => template.activity_title || template.title,
      "starts_at" => input_text(starts_at),
      "ends_at" => input_text(finish(starts_at, template)),
      "enough_at" => number_text(template.enough_at),
      "full_at" => number_text(template.full_at),
      "place" => template.place,
      "coordinate" => template.coordinate,
      "hours" => template.hours,
      "description" => template.description
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc """
  `params` with Finish moved to keep `template`'s duration after Start, which just changed
  (#747). A template with no duration leaves Finish as typed.
  """
  def follow_start(params, %Template{} = template) do
    case finish(cast_naive(params["starts_at"]), template) do
      nil -> params
      ends_at -> Map.put(params, "ends_at", input_text(ends_at))
    end
  end

  defp finish(%NaiveDateTime{} = starts_at, %Template{duration_minutes: minutes})
       when is_integer(minutes),
       do: NaiveDateTime.add(starts_at, minutes, :minute)

  defp finish(_starts_at, _template), do: nil

  defp cast_naive(value) do
    case Ecto.Type.cast(:naive_datetime, value) do
      {:ok, %NaiveDateTime{} = naive} -> naive
      _blank_or_not_a_time -> nil
    end
  end

  defp number_text(nil), do: nil
  defp number_text(n), do: Integer.to_string(n)

  # As the browser's date-and-time box takes it, to the minute.
  defp input_text(nil), do: nil
  defp input_text(naive), do: Calendar.strftime(naive, "%Y-%m-%dT%H:%M")

  def changeset(%__MODULE__{} = form, params \\ %{}) do
    form
    |> cast(
      params,
      [
        :template_id,
        :kind,
        :title,
        :description,
        :place,
        :coordinate,
        :tracking_number,
        :starts_at,
        :ends_at,
        :enough_at,
        :full_at,
        :hours,
        :published
      ],
      message: &Activity.number_message/2
    )
    |> validate_required([:title], message: "Enter a title.")
    |> validate_required([:starts_at], message: "Enter when it starts.")
    |> validate_required([:ends_at], message: "Enter when it finishes.")
    |> validate_inclusion(:kind, Enum.map(@kinds, &elem(&1, 1)))
    |> validate_inclusion(:hours, Enum.map(@hours, &elem(&1, 1)))
    |> validate_length(:title, max: 100)
    |> validate_length(:place, max: 100)
    |> Coordinate.put_pin()
    |> validate_length(:tracking_number, max: 50)
    |> validate_length(:description, max: 10_000)
    |> validate_ends_after_starts()
    |> Activity.validate_enough_and_full()
    |> Validate.in_field_order(@fields)
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

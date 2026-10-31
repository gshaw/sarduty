defmodule App.Model.Template do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Model.Team
  alias App.Model.Template
  alias App.Model.TemplateGroup
  alias App.Model.TemplateItem
  alias App.Model.TemplateTag
  alias App.Repo
  alias App.Validate

  # A named set of equipment items, each with default hours, tags, and groups whose
  # members it adds, that a team admin applies to an activity in one step (#271, #162). Templates are SAR Duty's
  # own; D4H never sees them. A template for one kind of activity also holds values for
  # that kind's D4H custom fields (#307), keyed by D4H field id as on activities, and the
  # details that fill Add activity (#746). Applying a template leaves the details out,
  # but for its Tax credit hours on an activity with no hours tag (apply_tags/4), and its
  # Enough at and Full at on an open activity with neither (ApplyTemplate.numbers/4).
  schema "templates" do
    belongs_to :team, Team
    has_many :template_items, TemplateItem, on_replace: :delete
    has_many :template_tags, TemplateTag, on_replace: :delete
    has_many :template_groups, TemplateGroup, on_replace: :delete
    field :title, TrimmedString
    # "incident", "exercise", or "event"; nil for any kind, which holds no field values.
    field :activity_kind, :string
    field :custom_values, :map
    # The activity's details (#746), each optional. A blank title uses the template's.
    field :activity_title, TrimmedString
    field :start_time, :time
    field :duration_minutes, :integer
    # The duration as Change template takes it: "2h 30m" (Service.Convert.parse_duration/1).
    field :duration, :string, virtual: true
    # How many signed up is enough, and full (#447), as on the activity form.
    field :enough_at, :integer
    field :full_at, :integer
    field :place, TrimmedString
    # The place's pin, "lat,lng" as the sync stores it, or nil (#610).
    field :coordinate, :string
    # Tax credit hours: "primary", "secondary", or "none", as on the activity form. It
    # sets the hours tag, so a template's tags never hold one.
    field :hours, :string, default: "primary"
    field :description, TrimmedString
    timestamps(type: :utc_datetime_usec)
  end

  @preloads [template_items: :equipment_item, template_tags: :tag, template_groups: :group]

  @kinds ~w(incident exercise event)

  @hours ~w(primary secondary none)
  @fields [
    :title,
    :activity_kind,
    :activity_title,
    :start_time,
    :duration,
    :enough_at,
    :full_at,
    :place,
    :coordinate,
    :hours,
    :description
  ]

  @doc """
  Change template: its name and kind, and the details that fill Add activity (#746). The
  duration is typed as a chore's time is. The other change pages send none of these, so
  each is left as it is.
  """
  def build_changeset(%Template{} = data, params \\ %{}) do
    data
    |> Map.put(:duration, Service.Convert.duration_text(data.duration_minutes))
    |> cast(params, @fields, message: &Activity.number_message/2)
    |> validate_required([:title], message: "Enter a name for the template")
    |> validate_length(:title, max: 100)
    |> validate_inclusion(:activity_kind, @kinds)
    |> validate_length(:activity_title, max: 100)
    |> validate_length(:place, max: 100)
    |> validate_length(:description, max: 10_000)
    |> update_change(:description, &Service.DescriptionHTML.clean/1)
    |> validate_inclusion(:hours, @hours)
    |> Coordinate.put_pin()
    |> put_duration_minutes()
    |> Activity.validate_enough_and_full()
    |> Validate.in_field_order(@fields)
  end

  # A week at most, so a slip of the keys can't make a month-long activity.
  @max_minutes 7 * 24 * 60

  defp put_duration_minutes(changeset) do
    if changed?(changeset, :duration), do: read_duration(changeset), else: changeset
  end

  defp read_duration(changeset) do
    text = changeset |> get_field(:duration) |> to_string() |> String.trim()

    case Service.Convert.parse_duration(text) do
      _blank when text == "" -> put_change(changeset, :duration_minutes, nil)
      nil -> add_error(changeset, :duration, "Enter the duration like 45m, 2h, or 2.5h.")
      0 -> add_error(changeset, :duration, "Enter a duration over 0.")
      minutes when minutes > @max_minutes -> add_error(changeset, :duration, "Enter up to 168h.")
      minutes -> put_change(changeset, :duration_minutes, minutes)
    end
  end

  @doc "The kinds a template can be for, as the form offers them."
  def kind_options,
    do: [{"Any kind", ""}, {"Incident", "incident"}, {"Exercise", "exercise"}, {"Event", "event"}]

  @doc "The kind a template is for, as the form names it, or nil for any kind."
  def kind_label(%Template{activity_kind: nil}), do: nil

  def kind_label(%Template{activity_kind: kind}),
    do: Enum.find_value(kind_options(), fn {label, value} -> value == kind && label end)

  @doc "A team's templates by title, with their items, tags, and groups."
  def get_all(team_id) do
    Template
    |> where([k], k.team_id == ^team_id)
    |> order_by([k], asc: k.title, asc: k.id)
    |> preload(^@preloads)
    |> Repo.all()
  end

  def find!(%Team{} = team, id) do
    Template
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload(@preloads)
  end

  @doc "The template's tags by title."
  def tags(%Template{template_tags: template_tags}),
    do: template_tags |> Enum.map(& &1.tag) |> Enum.sort_by(&String.downcase(&1.title))

  @doc """
  The tags applying the template adds to an activity whose tags are `titles`: its own,
  and the hours tag its Tax credit hours names, from the team's `team_tags`, while
  `titles` hold no hours tag. Hours someone chose are never changed. `hours_tags` is
  `Activity.hours_tags/1`.
  """
  def apply_tags(%Template{} = template, titles, team_tags, hours_tags) do
    title = !Activity.hours_tagged?(titles, hours_tags) && hours_title(template, hours_tags)
    hours_tag = title && Enum.find(team_tags, &(&1.title == title))
    if hours_tag, do: [hours_tag | tags(template)], else: tags(template)
  end

  defp hours_title(%Template{hours: "primary"}, hours_tags), do: hours_tags.primary
  defp hours_title(%Template{hours: "secondary"}, hours_tags), do: hours_tags.secondary
  defp hours_title(%Template{}, _hours_tags), do: nil

  @doc "The groups whose members the template adds, by title."
  def groups(%Template{template_groups: template_groups}),
    do: template_groups |> Enum.map(& &1.group) |> Enum.sort_by(&String.downcase(&1.title))
end

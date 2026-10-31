defmodule App.Model.Template do
  use App, :model

  alias App.Field.TrimmedString
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
  # details that fill Add activity (#746). Applying a template leaves the details out.
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
    field :length_minutes, :integer
    # The length as Change details takes it, in hours ("2.5").
    field :length, :string, virtual: true
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

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:title, :activity_kind])
    |> validate_required([:title], message: "Enter a name for the template")
    |> validate_length(:title, max: 100)
    |> validate_inclusion(:activity_kind, @kinds)
  end

  @hours ~w(primary secondary none)
  @detail_fields [
    :activity_title,
    :start_time,
    :length,
    :place,
    :coordinate,
    :hours,
    :description
  ]

  @doc "Change details (#746). The length is typed in hours."
  def build_details_changeset(%Template{} = data, params \\ %{}) do
    data
    |> Map.put(:length, length_text(data.length_minutes))
    |> cast(params, @detail_fields)
    |> validate_length(:activity_title, max: 100)
    |> validate_length(:place, max: 100)
    |> validate_length(:description, max: 10_000)
    |> update_change(:description, &Service.DescriptionHTML.clean/1)
    |> validate_inclusion(:hours, @hours)
    |> Coordinate.put_pin()
    |> put_length_minutes()
    |> Validate.in_field_order(@detail_fields)
  end

  defp length_text(nil), do: nil
  defp length_text(minutes), do: Service.Convert.minutes_to_hours(minutes)

  # A week at most, so a slip of the keys can't make a month-long activity.
  defp put_length_minutes(changeset) do
    text = changeset |> get_field(:length) |> to_string() |> String.trim()

    case Float.parse(text) do
      _blank when text == "" ->
        put_change(changeset, :length_minutes, nil)

      {hours, ""} when hours > 0 and hours <= 168 ->
        put_change(changeset, :length_minutes, Service.Convert.hours_to_minutes(hours))

      _other ->
        add_error(changeset, :length, "Enter the length in hours, such as 2.5.")
    end
  end

  @doc "Whether the template has a start time or a length: the Start column's test."
  def starts?(%Template{start_time: time, length_minutes: minutes}),
    do: time != nil or minutes != nil

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

  @doc "The groups whose members the template adds, by title."
  def groups(%Template{template_groups: template_groups}),
    do: template_groups |> Enum.map(& &1.group) |> Enum.sort_by(&String.downcase(&1.title))
end

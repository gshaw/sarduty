defmodule App.Model.CustomField do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Repo

  # A copy of one of D4H's custom fields (#681), kept by the sync: the team's own or its
  # organisation's, for activities, members, and equipment. Values live on the records,
  # in `custom_values`, keyed by the D4H field id as a string. Choice values are lists
  # of D4H option ids, which `options` names. See docs/custom-fields.md.
  schema "custom_fields" do
    belongs_to :team, Team
    field :d4h_custom_field_id, :integer
    # "event", "exercise", "incident", "member", or "equipment".
    field :target, :string
    field :title, TrimmedString
    # D4H's type, lowercased: "text", "text_area", "number", "date", "datetime", "time",
    # "single_choice", or "multiple_choice".
    field :field_type, :string
    field :required, :boolean, default: false
    # D4H's RESTRICTED. On a team's own field it keeps the value from its organisation:
    # team admins see it, never members or anything an organisation sees.
    field :restricted, :boolean, default: false
    # "hidden", "viewable", or "editable": what a member may do with their own value.
    field :member_privacy, :string
    field :hint, :string
    field :value_units, :string
    field :ordering, :integer, default: 0
    # "Team" or "Organisation" and its D4H id, as for tags.
    field :owner_type, :string
    field :owner_id, :integer
    field :archived_at, :utc_datetime
    # [%{"id" => d4h_option_id, "label" => …, "ordering" => …, "archived" => bool}]
    field :options, {:array, :map}, default: []
    timestamps(type: :utc_datetime_usec)
  end

  @doc "A team's fields for one target, in D4H's order. Archived ones are left out."
  def get_all(team_id, target) do
    CustomField
    |> where([f], f.team_id == ^team_id and f.target == ^target and is_nil(f.archived_at))
    |> order_by([f], asc: f.ordering, asc: f.title, asc: f.id)
    |> Repo.all()
  end

  @doc "A team's fields by D4H id, archived ones too, for naming stored values."
  def index(team_id) do
    CustomField
    |> where([f], f.team_id == ^team_id)
    |> Repo.all()
    |> Map.new(&{Integer.to_string(&1.d4h_custom_field_id), &1})
  end

  def organisation?(%CustomField{owner_type: owner_type}), do: owner_type == "Organisation"

  def choice?(%CustomField{field_type: type}), do: type in ~w(single_choice multiple_choice)

  @doc """
  A stored value as text people read. Option ids become their labels, and dates are
  formatted. A value D4H sent in a shape this doesn't know is shown as it came.
  """
  def display(%CustomField{} = field, value, _timezone) when is_list(value) do
    labels = Map.new(field.options, &{&1["id"], &1["label"]})
    Enum.map_join(value, ", ", &Map.get(labels, &1, "Option #{&1}"))
  end

  def display(%CustomField{field_type: "date"}, value, _timezone) when is_binary(value) do
    case value |> String.slice(0, 10) |> Date.from_iso8601() do
      {:ok, date} -> Service.Format.date_short(date)
      _error -> value
    end
  end

  def display(%CustomField{field_type: "datetime"}, value, timezone) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> Service.Format.datetime_short(at, timezone)
      _error -> value
    end
  end

  def display(%CustomField{value_units: units}, value, _timezone)
      when is_binary(value) and is_binary(units),
      do: "#{value} #{units}"

  def display(%CustomField{}, value, _timezone), do: to_string(value)

  @doc """
  A record's values as `%{"title" => text}` for the fields in `ids`, for history. A
  field the copy doesn't know is named by its D4H id.
  """
  def describe_values(index, values, ids, timezone) do
    Map.new(ids, fn id ->
      case index[id] do
        nil -> {"Field #{id}", values[id] && inspect(values[id])}
        field -> {field.title, values[id] && display(field, values[id], timezone)}
      end
    end)
  end
end

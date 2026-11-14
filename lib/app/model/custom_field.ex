defmodule App.Model.CustomField do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle
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
    # D4H's RESTRICTED. On an activity or equipment field it keeps the value from its
    # organisation: team admins see it, never members or anything an organisation sees.
    # On a member field it changes nothing in SAR Duty (#1056).
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
    # D4H's resource bundle, a named group of one kind's fields, or nil (#872).
    belongs_to :bundle, CustomFieldBundle
    # When D4H says the field was added.
    field :d4h_created_at, :utc_datetime
    # D4H's own flags, copied for #724: searchable in D4H, and frozen, which a key can't
    # change.
    field :searchable, :boolean, default: false
    field :frozen, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end

  @targets ~w(incident exercise event member equipment)

  @doc "A team's fields for one target, in D4H's order. Archived ones are left out."
  def get_all(team_id, target) do
    CustomField
    |> where([f], f.team_id == ^team_id and f.target == ^target and is_nil(f.archived_at))
    |> ordered()
    |> Repo.all()
  end

  @doc """
  Every field a team has, archived ones too, in D4H's order, for its Fields page (#872).
  """
  def get_all_with_archived(team_id) do
    CustomField
    |> where([f], f.team_id == ^team_id)
    |> ordered()
    |> Repo.all()
  end

  @doc "One of the team's fields by its local id, with its bundle."
  def get_for_team!(team_id, id) do
    CustomField |> preload(:bundle) |> Repo.get_by!(id: id, team_id: team_id)
  end

  @doc """
  An organization's own fields, archived ones too, from its teams' copies (#872). D4H
  gives every team its organization's fields, so each one is here once per team; the
  Fields page folds them with `merge_copies/2`.
  """
  def get_all_organisation(team_ids) do
    CustomField
    |> where([f], f.team_id in ^team_ids and f.owner_type == "Organisation")
    |> ordered()
    |> Repo.all()
  end

  defp ordered(query) do
    query
    |> order_by([f], asc: f.ordering, asc: f.title, asc: f.id)
    |> preload(:bundle)
  end

  @doc """
  One of an organization's fields, by the local id of one team's copy, folded with its
  other teams' copies by merge_copies/1. Raises Ecto.NoResultsError when no team in
  `team_ids` has an organization's field with that id.
  """
  def get_organisation!(team_ids, id) do
    copies = get_all_organisation(team_ids)

    copy =
      Enum.find(copies, &(to_string(&1.id) == to_string(id))) ||
        raise Ecto.NoResultsError, queryable: CustomField

    [field] =
      copies
      |> Enum.filter(
        &(&1.owner_id == copy.owner_id and &1.d4h_custom_field_id == copy.d4h_custom_field_id)
      )
      |> merge_copies()

    field
  end

  @doc """
  How many live fields each target has, `[{target, count}]` in the Fields pages' order.
  A target with only archived fields counts 0, so its archived ones can still be opened.
  """
  def counts_by_target(fields) do
    for {target, fields} <- by_target(fields),
        do: {target, Enum.count(fields, &is_nil(&1.archived_at))}
  end

  @doc """
  Each of an organization's fields once, from its teams' copies, in D4H's order: one
  team's copy, with every choice any team's copy has. A choice a team added keeps its
  owner, so the page can say which team added it.
  """
  def merge_copies(copies) do
    copies
    |> Enum.group_by(&{&1.owner_id, &1.d4h_custom_field_id})
    |> Enum.map(fn {_key, [first | _rest] = same} ->
      options = same |> Enum.flat_map(& &1.options) |> Enum.uniq_by(& &1["id"])
      %{first | options: options}
    end)
    |> Enum.sort_by(&{&1.ordering, &1.title, &1.id})
  end

  @doc """
  `items` in groups, as the pages show them (#872): `[{nil, items}, {bundle, items}, …]`.
  The ones in no bundle come first, then each bundle by D4H's ordering and its id. Each
  group keeps the order `items` came in, and empty groups are left out. `to_field` finds
  the field in an item, such as a row from `rows/4`; its bundle must be preloaded.
  """
  def grouped(items, to_field \\ & &1) do
    # By D4H's id, so an organization's fields from several teams' copies share one group.
    groups = Enum.group_by(items, &bundle_key(to_field.(&1)))

    groups
    |> Enum.map(fn {key, [first | _rest] = group} ->
      {key && to_field.(first).bundle, group}
    end)
    |> Enum.sort_by(fn
      {nil, _group} -> {0, 0, 0}
      {bundle, _group} -> {1, bundle.ordering, bundle.d4h_bundle_id}
    end)
  end

  defp bundle_key(%CustomField{bundle: nil}), do: nil

  defp bundle_key(%CustomField{bundle: %CustomFieldBundle{} = bundle}),
    do: {bundle.owner_type, bundle.owner_id, bundle.d4h_bundle_id}

  @doc """
  `fields` by what they're on, as `[{target, fields}]` in the order the Fields pages list
  them. Each keeps the order it came in, and targets with none are left out.
  """
  def by_target(fields) do
    groups = Enum.group_by(fields, & &1.target)
    for target <- @targets, Map.has_key?(groups, target), do: {target, groups[target]}
  end

  @doc "A target's heading on the Fields pages."
  def target_title("incident"), do: "Incidents"
  def target_title("exercise"), do: "Exercises"
  def target_title("event"), do: "Events"
  def target_title("member"), do: "Members"
  def target_title("equipment"), do: "Equipment"

  @doc ~s(What a field holds, in words: "Long text", "One choice", and so on.)
  def type_label("text"), do: "Text"
  def type_label("text_area"), do: "Long text"
  def type_label("number"), do: "Number"
  def type_label("date"), do: "Date"
  def type_label("datetime"), do: "Date and time"
  def type_label("time"), do: "Time"
  def type_label("single_choice"), do: "One choice"
  def type_label("multiple_choice"), do: "Several choices"
  def type_label(type), do: type |> String.replace("_", " ") |> String.capitalize()

  @doc ~s(What a member may do with their own value of a member field, in words.)
  def member_privacy_label("viewable"), do: "See their own"
  def member_privacy_label("editable"), do: "Change their own"
  def member_privacy_label(_hidden), do: "Hidden"

  @doc "A team's fields by D4H id, archived ones too, for naming stored values."
  def index(team_id) do
    CustomField
    |> where([f], f.team_id == ^team_id)
    |> Repo.all()
    |> Map.new(&{Integer.to_string(&1.d4h_custom_field_id), &1})
  end

  @doc """
  The member fields `viewer` sees on one member, in order (#1056): every live one for a
  team admin, and for the member themself the ones D4H lets a member see
  (`member_privacy` viewable or editable). RESTRICTED changes nothing on a member field.
  """
  def member_fields(team_id, viewer) when viewer in [:team_admin, :self] do
    team_id
    |> get_all("member")
    |> Enum.filter(&(viewer == :team_admin or member_sees?(&1)))
  end

  @doc "Whether a member sees their own value of a member field: D4H's member privacy."
  def member_sees?(%CustomField{member_privacy: privacy}), do: privacy in ~w(viewable editable)

  @doc "Whether a member changes their own value of a member field: D4H's `editable`."
  def member_changes?(%CustomField{member_privacy: privacy}), do: privacy == "editable"

  def organisation?(%CustomField{owner_type: owner_type}), do: owner_type == "Organisation"

  @activity_targets ~w(incident exercise event)

  @doc "Whether `target` is an activity's kind: incidents, exercises, and events."
  def activity_target?(target), do: target in @activity_targets

  @doc "Every target a team adds a field to, in the Fields pages' order."
  def targets, do: @targets

  @doc """
  Whether a team admin changes `field` in SAR Duty (#1056 step 4): the team's own, not
  `frozen`, with a key that can change fields. An organization's field is read only.
  """
  def team_changes?(%Team{} = team, %CustomField{} = field),
    do: Team.d4h_can?(team, :custom_fields) and field.owner_type == "Team" and not field.frozen

  @doc """
  How many of the team's records hold an answer to `field`, read from the copy, for
  Delete (#1056). A record whose values aren't copied yet (nil) counts as one, since it
  may hold one. A deleted activity doesn't count.
  """
  def answer_count(%CustomField{team_id: team_id, target: target} = field) do
    key = ~s($."#{field.d4h_custom_field_id}")

    target
    |> answer_query(team_id)
    |> where(
      [r],
      is_nil(r.custom_values) or not is_nil(fragment("json_extract(?, ?)", r.custom_values, ^key))
    )
    |> Repo.aggregate(:count)
  end

  defp answer_query("member", team_id), do: where(App.Model.Member, team_id: ^team_id)
  defp answer_query("equipment", team_id), do: where(App.Model.EquipmentItem, team_id: ^team_id)

  defp answer_query(kind, team_id) when kind in @activity_targets do
    Activity
    |> where(team_id: ^team_id, activity_kind: ^kind)
    |> Activity.not_deleted()
  end

  @doc """
  Whether `title` names another live field of `target`, the team's or its
  organization's, ignoring case and spaces at either end. `except` is the field being
  changed, which keeps its own name.
  """
  def title_taken?(fields, target, title, except \\ nil) do
    wanted = comparable(title)

    Enum.any?(fields, fn field ->
      field.target == target and is_nil(field.archived_at) and field.id != (except && except.id) and
        comparable(field.title) == wanted
    end)
  end

  defp comparable(title), do: title |> to_string() |> String.trim() |> String.downcase()

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
  What a record's page shows, from the target's live `fields` in order and the record's
  `values`: each field with a value, and each required one without, as
  `%{field:, text:, missing?:}`. RESTRICTED activity and equipment fields are left out
  unless `restricted: true`; on a member field it changes nothing, since member_fields/2
  already picked what the viewer sees. Required ones are only marked missing with
  `missing: true`.
  """
  def rows(fields, values, timezone, opts \\ []) do
    values = values || %{}
    restricted? = Keyword.get(opts, :restricted, false)
    missing? = Keyword.get(opts, :missing, false)

    Enum.flat_map(fields, fn field ->
      value = values[Integer.to_string(field.d4h_custom_field_id)]

      cond do
        field.restricted and field.target != "member" and not restricted? -> []
        value != nil -> [%{field: field, text: display(field, value, timezone), missing?: false}]
        missing? and field.required -> [%{field: field, text: nil, missing?: true}]
        true -> []
      end
    end)
  end

  @doc """
  For a team admin's forms, the count over an activity's missing fields, as on its Fields
  tab: `{missing, required}` when its kind's `fields` flag some (a draft incident), or
  nil.
  """
  def missing_count(fields, %{custom_values: values} = activity, timezone) do
    rows =
      rows(fields, values, timezone,
        restricted: true,
        missing: Activity.flag_missing_fields?(activity)
      )

    case Enum.count(rows, & &1.missing?) do
      0 -> nil
      missing -> {missing, Enum.count(fields, & &1.required)}
    end
  end

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

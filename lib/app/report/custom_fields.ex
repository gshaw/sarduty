defmodule App.Report.CustomFields do
  @moduledoc """
  A team's D4H custom fields as report fields (#840).

  A query names one by its title in backticks, as Sheets' QUERY language quotes a name
  with spaces: `` `Primary Cause` ``, or ``activity.`Task Type` `` from a parent. Titles
  match whatever their case. A report reads what a record's Fields tab shows: live fields
  only, an activity's for its kind, a member's only when the team copies it, never a
  RESTRICTED one for a member.

  The values are `custom_values`, a map of D4H field id to a string or a list of option
  ids (docs/custom-fields.md), read with SQLite's `json_extract`. Field ids come from the
  copy of D4H's definitions, never from a query, so they are written inline; option
  labels are parameters.

  - A choice is its option's label, so two fields that share a title (an event's and an
    exercise's Event Leader) group and compare by the same words.
  - A multiple choice is a list of labels, like tags: `includes`, `excludes`.
  - A number is the number D4H's text holds, or blank when it holds none.
  - A date is a day, not a moment: the start of that day in the team's time zone, so
    `year()`, ranges, and formats read it as they read `started_at`, and Jan 1 never
    slips back to Dec 31.
  """

  import Ecto.Query, only: [where: 3, order_by: 3]

  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Report.Context
  alias App.Report.Field
  alias App.Report.LocalTime
  alias App.Report.SQL

  @kinds ~w(incident exercise event)
  @kind_words %{"incident" => "incidents", "exercise" => "exercises", "event" => "events"}

  @doc """
  The team's fields a report can read, by subject: `%{"activities" => [def], …}`. Each
  def is a map with the field's `title`, report `type`, the D4H `ids` it reads, its
  `kinds`, `options` as `{id, label}`, and whether it is `restricted`. Read once for a
  Context.
  """
  def read(%Team{} = team, repo), do: team |> live_fields(repo) |> by_subject()

  defp live_fields(team, repo) do
    CustomField
    |> where([f], f.team_id == ^team.id and is_nil(f.archived_at))
    |> order_by([f], asc: f.ordering, asc: f.title, asc: f.id)
    |> repo.all()
  end

  defp by_subject(fields) do
    %{
      "activities" => fields |> Enum.filter(&(&1.target in @kinds)) |> defs(),
      "members" => fields |> Enum.filter(&(&1.target == "member" and &1.copy_values)) |> defs(),
      "equipment" => fields |> Enum.filter(&(&1.target == "equipment")) |> defs(),
      # D4H's member fields the team doesn't copy, so a query naming one hears why.
      uncopied: fields |> Enum.filter(&(&1.target == "member")) |> uncopied_titles()
    }
  end

  defp uncopied_titles(member_fields) do
    for f <- member_fields, f.restricted or not f.copy_values, into: %{} do
      {String.downcase(f.title), if(f.restricted, do: :restricted, else: :uncopied)}
    end
  end

  # One def per title. Fields that share a title on different kinds are one field, read
  # from whichever the activity's kind has; on the same kind they're a mistake to name.
  defp defs(fields) do
    fields
    |> Enum.reject(&(&1.restricted and &1.target == "member"))
    |> Enum.group_by(&String.downcase(&1.title))
    |> Enum.map(fn {_key, same} -> definition(same) end)
    |> Enum.sort_by(& &1.order)
  end

  defp definition([first | _] = same) do
    same
    |> read_as()
    |> Map.merge(kinds(same))
    |> Map.merge(%{
      title: first.title,
      fields: same,
      ids: Enum.map(same, & &1.d4h_custom_field_id),
      options: Enum.flat_map(same, &options/1),
      order: {kind_order(first.target), first.ordering, first.title}
    })
  end

  defp kinds(same) do
    %{
      kinds: same |> Enum.map(& &1.target) |> Enum.uniq(),
      duplicate?: duplicate_kind?(same),
      restricted?: Enum.any?(same, & &1.restricted),
      units: Enum.find_value(same, & &1.value_units)
    }
  end

  # Fields that share a title and read differently read as text.
  defp read_as(same) do
    case same |> Enum.map(&type(&1.field_type)) |> Enum.uniq() do
      [type] -> %{type: type, mixed?: false}
      _types -> %{type: :text, mixed?: true}
    end
  end

  defp duplicate_kind?(same), do: length(same) != length(Enum.uniq_by(same, & &1.target))

  defp kind_order(target), do: Enum.find_index(@kinds, &(&1 == target)) || 0

  defp options(%CustomField{options: options}),
    do: for(o <- options || [], do: {o["id"], o["label"]})

  @doc "The report type a D4H type reads as."
  def type(type) when type in ~w(text text_area time), do: :text
  def type("number"), do: :number
  def type(type) when type in ~w(date datetime), do: :date
  def type("single_choice"), do: :choice
  def type("multiple_choice"), do: :list
  def type(_other), do: :text

  @doc "`:restricted` or `:uncopied` for a member field D4H has and the team doesn't copy."
  def uncopied(%Context{custom_fields: custom}, "`" <> _ = name),
    do:
      custom |> Map.get(:uncopied, %{}) |> Map.get(name |> String.trim("`") |> String.downcase())

  @doc "The defs `context`'s viewer may read in `subject_name`."
  def all(%Context{custom_fields: custom}, subject_name), do: Map.get(custom, subject_name, [])

  @doc "The catalog field for each def of `subject_name`."
  def fields(%Context{} = context, subject_name),
    do: for(d <- all(context, subject_name), do: field(d, subject_name))

  @doc "The catalog field for `name`, a title in backticks, or nil."
  def find(%Context{} = context, subject_name, "`" <> _ = name) do
    title = name |> String.trim("`") |> String.downcase()

    context
    |> all(subject_name)
    |> Enum.find(&(String.downcase(&1.title) == title))
    |> then(&(&1 && field(&1, subject_name)))
  end

  def find(_context, _subject_name, _name), do: nil

  defp field(d, subject_name) do
    %Field{
      name: "`#{d.title}`",
      label: d.title,
      type: d.type,
      about: about(d, subject_name),
      custom: d,
      choices: choices(d),
      shown: shown(d, subject_name)
    }
  end

  # Team admins see a RESTRICTED activity field; members see the rest, as on its Fields
  # tab. A member's and an item's fields are for team admins.
  defp shown(%{restricted?: true}, "activities"), do: &team_admin?/1
  defp shown(_d, "activities"), do: nil
  defp shown(_d, _subject), do: &team_admin?/1

  defp team_admin?(%Context{team_admin?: team_admin?}), do: team_admin?

  defp choices(%{type: type, options: options}) when type in [:choice, :list] do
    labels = options |> Enum.map(&elem(&1, 1)) |> Enum.uniq_by(&String.downcase/1)
    fn _context -> Enum.map(labels, &{&1, &1}) end
  end

  defp choices(_d), do: nil

  defp about(d, subject_name) do
    [where_text(d, subject_name), type_text(d), units_text(d), restricted_text(d)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp where_text(%{kinds: kinds}, "activities"),
    do: "On #{kinds |> Enum.map(&@kind_words[&1]) |> Service.Format.and_list()}."

  defp where_text(_d, _subject), do: nil

  defp type_text(%{mixed?: true}), do: "Text: its kinds hold it differently."

  defp type_text(%{type: :choice} = d), do: "One of #{some(d)}."
  defp type_text(%{type: :list} = d), do: "Any of #{some(d)}."
  defp type_text(%{type: :number}), do: "A number."
  defp type_text(%{type: :date, fields: [%{field_type: "date"} | _]}), do: "A day."
  defp type_text(%{type: :date}), do: "A date and time."
  defp type_text(_d), do: "Text."

  defp some(d) do
    labels = d.options |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    case Enum.split(labels, 3) do
      {first, []} -> first |> Enum.map(&"'#{&1}'") |> Service.Format.or_list()
      {first, rest} -> Enum.map_join(first, ", ", &"'#{&1}'") <> ", and #{length(rest)} more"
    end
  end

  defp units_text(%{units: units}) when is_binary(units), do: "In #{units}."
  defp units_text(_d), do: nil

  defp restricted_text(%{restricted?: true}), do: "Restricted: team admins only."
  defp restricted_text(_d), do: nil

  @doc """
  The field's SQL in `table`, `{iodata, params}`: each field it reads, the first with a
  value. A def that shares its title on one kind fails, as a query can't tell them apart.
  """
  def sql(%{fields: fields} = d, table, %Context{timezone: timezone}) do
    parts = Enum.map(fields, &one(&1, d, table, timezone))

    case parts do
      [one] -> one
      many -> SQL.join([{"COALESCE(", []}, SQL.join(many, ", "), {")", []}])
    end
  end

  # Mixed types read as text: a choice's label, a list's labels, anything else as written.
  defp one(field, %{mixed?: true}, table, _timezone), do: text_sql(field, table)

  defp one(%CustomField{field_type: type} = field, _d, table, timezone),
    do: typed(type, field, table, timezone)

  defp typed("number", field, table, _timezone), do: {number_sql(value(field, table)), []}

  # A day as the start of that day in the team's zone, stored as a UTC time is.
  defp typed("date", field, table, timezone),
    do: {LocalTime.day_start(["date(", value(field, table), ")"], timezone), []}

  defp typed("datetime", field, table, _timezone),
    do: {["strftime('%Y-%m-%dT%H:%M:%SZ', ", value(field, table), ")"], []}

  defp typed("single_choice", field, table, _timezone), do: label_sql(first(field, table), field)

  defp typed("multiple_choice", field, table, _timezone) do
    {case_sql, params} = label_sql("j.value", field)

    # No value is blank, not an empty list, as a tag-less activity's tags are.
    {[
       "NULLIF((SELECT json_group_array(",
       case_sql,
       ") FROM json_each(",
       value(field, table),
       ") AS j), '[]')"
     ], params}
  end

  defp typed(_text, field, table, _timezone), do: {value(field, table), []}

  defp text_sql(%CustomField{field_type: "single_choice"} = field, table),
    do: label_sql(first(field, table), field)

  defp text_sql(%CustomField{field_type: "multiple_choice"} = field, table) do
    {case_sql, params} = label_sql("j.value", field)

    {[
       "(SELECT group_concat(",
       case_sql,
       ", ', ') FROM json_each(",
       value(field, table),
       ") AS j)"
     ], params}
  end

  defp text_sql(field, table), do: {value(field, table), []}

  # The text D4H sent as a number, or blank when it holds none: "N/A" isn't 0.
  @doc false
  def number_sql(text) do
    t = ["trim(", text, ")"]

    [
      "(CASE WHEN ",
      t,
      " GLOB '*[0-9]*' AND ",
      t,
      " NOT GLOB '*[^0-9.-]*' THEN CAST(",
      t,
      " AS NUMERIC) END)"
    ]
  end

  defp value(%CustomField{d4h_custom_field_id: id}, table) when is_integer(id),
    do: ["json_extract(", table, ".\"custom_values\", '$.\"", Integer.to_string(id), "\"')"]

  defp first(%CustomField{d4h_custom_field_id: id}, table) when is_integer(id),
    do: ["json_extract(", table, ".\"custom_values\", '$.\"", Integer.to_string(id), "\"[0]')"]

  # An option id as its label. Labels are D4H's text, so they're parameters.
  defp label_sql(id_sql, field) do
    case options(field) do
      [] ->
        {"NULL", []}

      options ->
        whens = Enum.map(options, fn _ -> " WHEN ? THEN ?" end)

        {["(CASE ", id_sql, whens, " END)"],
         Enum.flat_map(options, fn {id, label} -> [id, label] end)}
    end
  end
end

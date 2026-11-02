defmodule App.Report.Language do
  @moduledoc """
  How to write a report (#803): the language page at `/agents/reports`, and the same
  text as Markdown at `/agents/reports.md` for agents. Built from App.Report.Parser's
  clauses, functions, and ranges, App.Report.Formats, App.Report.Catalog's subjects and fields, and
  App.Report.Compiler's limits, so it cannot drift from the code. A test fails on a
  clause, function, or range with no entry here, and runs every example.

  It knows no team: a field's choices are listed only when they are the same for every
  team, and a field some teams or viewers cannot read says so.
  """

  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Report.Catalog
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Field
  alias App.Report.Formats
  alias App.Report.Parser
  alias Service.Format

  @example """
  select member, sum(hours)
  from attendance
  where status = 'Attended' and year(activity.started_at) = :year
    and member.counted = true
  group by member
  pivot activity.kind
  order by member.name
  totals
  filter year 'Year' required
    each year(activity.started_at)
  """

  # Each clause: how it's written, what it does, and an example a test checks.
  @clauses [
    {"select", "select field, …",
     "The columns, in order. A field, a function of one, or a count.",
     "select title, started_at, attended_count\nfrom activities"},
    {"from", "from subject", "The subject the rows come from. One per report.",
     "select name, joined_at\nfrom members"},
    {"where", "where condition", "Keeps the rows the condition is true for.",
     "select title, started_at\nfrom activities\nwhere kind = 'Incident' and started_at = THIS_YEAR"},
    {"group", "group by field, …",
     "One row for each value. Every other column is a count, sum, average, min, or max.",
     "select activity.kind, count(id)\nfrom attendance\nwhere status = 'Attended'\ngroup by activity.kind"},
    {"pivot", "pivot field",
     "A column for each value of the field, beside the group's own columns.",
     "select member, sum(hours)\nfrom attendance\nwhere status = 'Attended' and activity.started_at = THIS_YEAR\ngroup by member\npivot activity.kind"},
    {"order", "order by field [asc | desc] [nulls first | nulls last], …",
     "Sorts the rows. Going up unless it says desc.",
     "select name, last_attended\nfrom members\nwhere current = true\norder by last_attended desc nulls last"},
    {"limit", "limit n", "Shows only the first n rows.",
     "select title, attended_count\nfrom activities\norder by attended_count desc\nlimit 10"},
    {"offset", "offset n", "Skips the first n rows. Use it with limit.",
     "select title, attended_count\nfrom activities\norder by attended_count desc\nlimit 10\noffset 10"},
    {"label", "label field 'Label', …", "A column's heading, in place of the field's own.",
     "select title, attended_count\nfrom activities\nlabel attended_count 'Members'"},
    {"format", "format field as format, …",
     "How a column looks, in place of its field's own. Formats lists them.",
     "select title, started_at, attended_hours\nfrom activities\nformat title as text, started_at as month, attended_hours as hours"},
    {"totals", "totals", "A total row under a report that groups.",
     "select activity.kind, sum(hours)\nfrom attendance\nwhere status = 'Attended'\ngroup by activity.kind\ntotals"},
    {"search", "search field, …", "The search box. It looks for the words in each field named.",
     "select title, started_at\nfrom activities\nsearch title, ref_id, tags"},
    {"switch", "switch name 'Label' [required] [default value]",
     "The tiles above the rows, All first, each with its count. One per report, with an option for each tile.",
     "select title, started_at\nfrom activities\nswitch activity 'Kind'\n  option incident 'Incidents' where kind = 'incident'\n  option exercise 'Exercises' where kind = 'exercise'"},
    {"filter", "filter name 'Label' [required] [default value] [more]",
     "A menu, All first. required takes out All, default picks where it starts, and more puts it behind More filters.",
     "select title, started_at\nfrom activities\nfilter status 'Status'\n  option draft 'Draft' where published = false\n  option published 'Published' where published = true"},
    {"option", "option value 'Label' [where condition] [sort name [desc]]",
     "One tile or one menu choice, under a switch or filter: the value in the address, its label, and what it keeps.",
     "select title, started_at\nfrom activities\norder by started_at desc\nfilter when 'When'\n  option future 'Future' where started_at >= NOW sort date\n  option past 'Past' where started_at <= NOW\nsort date 'Date' started_at"},
    {"each", "each field [where condition]",
     "A menu choice for each value of the field, under a filter: each year, each of a choice's values, or each title.",
     "select title, started_at\nfrom activities\nwhere year(started_at) = :year\nfilter year 'Year' required default THIS_YEAR\n  each year(started_at)"},
    {"sort", "sort name 'Label' field [desc], …",
     "A column heading that sorts. Its label, or its first field, names the column.",
     "select title, started_at, attended_count\nfrom activities\nsort date 'Date' started_at desc\nsort attended 'Attended' attended_count desc"},
    {"page", "page n",
     "Shows n rows at a time, from 1 to #{Parser.max_page()}, with buttons for the rest.",
     "select title, started_at\nfrom activities\norder by started_at desc\npage 50"}
  ]

  @functions %{
    "count" => {"count(field), count(distinct field)", "How many rows, or how many values."},
    "sum" => {"sum(field)", "The numbers or hours added up."},
    "avg" => {"avg(field)", "The average."},
    "min" => {"min(field)", "The smallest, or the earliest date."},
    "max" => {"max(field)", "The largest, or the latest date."},
    "year" => {"year(date)", "The year, in the team's time zone: 2026."},
    "month" => {"month(date)", "The month, in the team's time zone."},
    "quarter" => {"quarter(date)", "The quarter: 1 to 4."},
    "lower" => {"lower(text)", "The text in small letters."},
    "upper" => {"upper(text)", "The text in capitals."},
    "days_since" => {"days_since(date)", "Whole days from the date to today."}
  }

  @ranges %{
    "NOW" => "This moment.",
    "TODAY" => "Today, in the team's time zone.",
    "THIS_MONTH" => "This month.",
    "LAST_MONTH" => "The whole month before this one.",
    "THIS_YEAR" => "This year, January 1 to December 31.",
    "LAST_YEAR" => "Last year.",
    "LAST_N_DAYS:n" => "Today and the n days before it, as whole days.",
    "NEXT_N_DAYS:n" => "Today and the n days after it.",
    "LAST_N_MONTHS:n" => "The n months before today, and today."
  }

  @args %{
    days: {"days", "A whole number of days: `not_seen(365)`."},
    period:
      {"period",
       "`'all'`, a year such as `'2026'`, or a number of days such as `'90d'`: the last 90 days."},
    tag: {"tag", "A tag's title, or `'all'`."},
    group: {"group", "A group's title, or `'all'`."}
  }

  @subjects %{
    "activities" => "Each row is an activity: an incident, exercise, or event.",
    "attendance" => "Each row is one member on one activity: their reply, or their attendance.",
    "members" => "Each row is a member, retired members too.",
    "awards" => "Each row is a qualification a member holds, or held.",
    "qualifications" => "Each row is one of the team's qualifications.",
    "equipment" => "Each row is an item: equipment, a vehicle, or a supply.",
    "equipment_use" => "Each row is an item used on an activity.",
    "groups" => "Each row is one of the team's groups."
  }

  @doc "The page's text, as Markdown."
  def markdown do
    Enum.join(
      [
        intro(),
        clauses(),
        conditions(),
        functions(),
        formats(),
        dates(),
        values(),
        subjects(),
        limits(),
        cannot()
      ],
      "\n\n"
    ) <> "\n"
  end

  @doc "Each clause's name, how it's written, what it does, and an example."
  def clause_entries, do: @clauses

  @doc "The functions' entries, by name."
  def function_entries, do: @functions

  @doc "The date ranges' entries, by name as written."
  def range_entries, do: @ranges

  @doc "Each subject's sentence, by name."
  def subject_entries, do: @subjects

  @doc "The kinds of field argument, by kind."
  def arg_entries, do: @args

  @doc "Every example query on the page: the first, then each clause's."
  def examples, do: [@example | Enum.map(@clauses, &elem(&1, 3))]

  defp intro do
    """
    # How to write a report

    A report is a query on one team's records: which fields to show, which rows to keep, \
    and how to sort them. Team admins write one on Reports, with New report. An agent can \
    read this page as text at `/agents/reports.md`.

    The language is Google Sheets' QUERY language, plus `from`, a dot to a parent's \
    fields, date ranges, and values picked when the report runs. Keywords, functions, and \
    date ranges ignore case. Text goes in single quotes.

    ```sql
    #{String.trim_trailing(@example)}
    ```

    This is Hours by member: each member's attended hours in the picked year, a column for \
    each kind of activity, and a total row.\
    """
  end

  defp clauses do
    {query, page} = Enum.split_with(@clauses, &(clause_name(&1) in query_clauses()))

    """
    ## The query

    The query's clauses come in this order, each at most once. Only `select` and `from` \
    are needed.

    #{clause_sections(query)}

    ## The page

    Clauses after the query draw the page around the rows: the search box, tiles, menus, \
    sortable headings, and pages. They come in this order: `search`, then each `switch` \
    and `filter` with its options, then each `sort`, then `page`.

    #{clause_sections(page)}\
    """
  end

  defp query_clauses, do: Parser.clauses()

  defp clause_name({name, _written, _does, _example}), do: name

  defp clause_sections(entries) do
    Enum.map_join(entries, "\n\n", fn {name, written, does, example} ->
      """
      ### #{heading(name)}

      `#{written}`

      #{does}

      ```sql
      #{example}
      ```\
      """
    end)
  end

  defp heading("group"), do: "group by"
  defp heading("order"), do: "order by"
  defp heading(name), do: name

  defp conditions do
    """
    ## Conditions

    A `where`, and an option's `where`, keep the rows a condition is true for.

    | Write | Is true when |
    | ----- | ------------ |
    | `=`, `!=`, `<`, `>`, `<=`, `>=` | The two sides compare that way. `<>` is `!=`. |
    | `contains 'river'` | The text has the words, in any case. |
    | `starts with 'Mt'`, `ends with 'Hut'` | The text starts or ends with them. |
    | `like '%river%'` | The text matches, with `%` for any text and `_` for one letter. |
    | `in ('incident', 'exercise')` | The value is one of the list's. `not in` is none of them. |
    | `includes ('Rope Rescue')` | A list field has any of the titles. `excludes` has none. |
    | `is null`, `is not null` | The field is blank, or is not. |
    | `and`, `or`, `not`, `( )` | Conditions together. `and` goes before `or`. |

    A value is a number, `true`, `false`, text in single quotes, a date such as \
    `date '2026-01-01'`, a date range, or a picked value such as `:year`. A choice \
    compares with its label or its value: `status = 'Attended'` and \
    `status = 'attended'` keep the same rows. A date compared with a date or a range \
    takes in whole days in the team's time zone: `started_at = LAST_YEAR`.\
    """
  end

  defp functions do
    rows =
      Enum.map_join(Parser.functions(), "\n", fn name ->
        {written, does} = Map.fetch!(@functions, name)
        "| `#{written}` | #{does} |"
      end)

    """
    ## Functions

    | Write | Gives |
    | ----- | ----- |
    #{rows}\
    """
  end

  defp formats do
    rows =
      Enum.map_join(Formats.by_type(), "\n", fn {type, formats} ->
        Enum.map_join(formats, "\n", fn {name, shows} -> "| #{type} | `#{name}` | #{shows} |" end)
      end)

    """
    ## Formats

    Each field draws its own cell: a date as a date, an activity's kind as its coloured \
    square, a member as a link to their page. `format` picks another look for a column. \
    The first for each type is the field's own. Other types show one way. Download CSV \
    keeps the values as they are.

    | For | Format | Shows |
    | --- | ------ | ----- |
    #{rows}\
    """
  end

  defp dates do
    rows =
      Enum.map_join(Parser.ranges(), "\n", fn name ->
        "| `#{name}` | #{Map.fetch!(@ranges, name)} |"
      end)

    """
    ## Dates

    Times are stored in UTC and read in the team's time zone. Compare a date field with a \
    range, as in `started_at = LAST_N_DAYS:30`, or with `<` and `>`.

    | Range | Takes in |
    | ----- | -------- |
    #{rows}

    "The last n days" means one thing everywhere in SAR Duty: today and the n days before \
    it, as whole days. Activities' Last 30 days and Members' Period count the same way.\
    """
  end

  defp values do
    rows =
      @args
      |> Map.values()
      |> Enum.map_join("\n", fn {name, holds} -> "| `#{name}` | #{holds} |" end)

    """
    ## Values picked when it runs

    A name after a colon, such as `:year`, is a value the team admin picks when the report \
    runs. A `filter` with the same name is its menu, and must be `required` when the query \
    reads the value: `where year(started_at) = :year` with `filter year 'Year' required`.

    Some fields take arguments in brackets, such as `activity_count('2026', 'all')`. An \
    argument can be a picked value, as in `activity_count(:when, :tag)`, and a filter with \
    that name and no options lists its menu by itself.

    | Argument | Is |
    | -------- | -- |
    #{rows}\
    """
  end

  defp subjects do
    sections = Enum.map_join(Catalog.subjects(), "\n\n", &subject_section/1)

    """
    ## Subjects and fields

    Each subject's rows are one team's. A field that names a parent record reaches its \
    fields with one dot: `member.name`, `activity.started_at`.

    #{sections}\
    """
  end

  defp subject_section(subject) do
    rows =
      subject.fields
      |> Enum.reject(& &1.hidden)
      |> Enum.map_join("\n", fn field ->
        "| `#{field_text(field)}` | #{type_text(field.type)} | #{holds(subject, field)} |"
      end)

    """
    ### #{subject.name}

    #{Map.fetch!(@subjects, subject.name)}

    | Field | Type | Holds |
    | ----- | ---- | ----- |
    #{rows}\
    """
  end

  @doc "A field as a query writes it, with its arguments: `not_seen(days)`."
  def field_text(%Field{name: name, args: []}), do: name

  def field_text(%Field{name: name, args: args}) do
    names = Enum.map_join(args, ", ", &elem(Map.fetch!(@args, &1), 0))
    "#{name}(#{names})"
  end

  defp type_text(:text), do: "text"
  defp type_text(:number), do: "number"
  defp type_text(:hours), do: "hours"
  defp type_text(:km), do: "km"
  defp type_text(:date), do: "date"
  defp type_text(:bool), do: "true or false"
  defp type_text(:list), do: "list"
  defp type_text(:choice), do: "choice"
  defp type_text({:record, kind}), do: "#{kind}, a link"

  defp holds(subject, field) do
    [
      field.about || "#{field.label}.",
      parent_text(subject, field),
      choices_text(field),
      list_text(field),
      who_text(field)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp parent_text(%{parents: parents}, %Field{parent: parent}) when is_binary(parent) do
    {subject_name, _fk} = Map.fetch!(parents, parent)
    "Reach its fields in #{subject_name} with a dot: `#{parent}.#{example_field(subject_name)}`."
  end

  defp parent_text(_subject, _field), do: nil

  defp example_field(subject_name) do
    subject = Catalog.subject(subject_name)
    Enum.find_value(subject.fields, &if(match?({:record, _}, &1.type), do: &1.name))
  end

  # Only a choice's values are the same for every team; a list's titles are the team's own.
  # A field whose about names them already says them once.
  defp choices_text(%Field{type: :choice, about: nil, choices: choices}) do
    labels = context() |> choices.() |> Enum.map_join(", ", &elem(&1, 0))
    "One of #{labels}."
  end

  defp choices_text(_field), do: nil

  defp list_text(%Field{type: :list}),
    do: "The team's own titles. Compare with `includes` or `excludes`."

  defp list_text(_field), do: nil

  # Who may read a field: its `shown` for a member and for a Records team, then the
  # choices a member doesn't see.
  defp who_text(%Field{} = field) do
    member = context(team_admin?: false)

    cond do
      not shown?(field, member) -> "Only team admins can read it."
      not shown?(field, context(records?: true)) -> "Only teams with custom fields have it."
      true -> hidden_text(field, member)
    end
  end

  defp shown?(%Field{shown: nil}, _context), do: true
  defp shown?(%Field{shown: shown}, context), do: shown.(context)

  defp hidden_text(%Field{hidden_choices: nil}, _member), do: nil

  defp hidden_text(%Field{hidden_choices: hidden_choices, choices: choices}, member) do
    hidden = hidden_choices.(member)

    case for({label, value} <- choices.(context()), value in hidden, do: label) do
      [] -> nil
      labels -> "Only team admins see #{Enum.join(labels, ", ")}."
    end
  end

  # A context with no team's data, for what every team's fields hold.
  defp context(opts \\ []) do
    host = if Keyword.get(opts, :records?, false), do: D4H.records_host()

    %Context{
      team: %Team{d4h_api_host: host},
      tags: [],
      groups: [],
      years: [],
      team_admin?: Keyword.get(opts, :team_admin?, true)
    }
  end

  defp limits do
    """
    ## Limits

    - A report shows at most #{Format.count(Compiler.max_rows(), one: "%d row", many: "%d rows")}. With `page`, each \
    page reads only its own rows, so there is no limit.
    - A pivot makes at most #{Format.count(Compiler.max_pivot(), one: "%d column", many: "%d columns")}.
    - A report stops after 2 seconds. Narrow it with `where`.\
    """
  end

  defp cannot do
    """
    ## What a report cannot do

    - Read contact details, addresses, coordinates, letter text, or keys. They are not \
    fields.
    - Change records. A report only reads.
    - Read another team's records.
    - Show every field with `select *`. Name each one.
    - Reach further than a parent's fields: `member.name` works, `attendance.member.name` \
    does not.
    - Have more than one `switch`. A report with `pivot` has no `switch`, `page`, or `sort`.\
    """
  end
end

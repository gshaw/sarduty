defmodule App.Report.Expr do
  @moduledoc """
  One expression of a query, checked against App.Report.Catalog and written as SQL.

  An expression is a map: `sql` and `params`; its `type`, a field type
  (App.Report.Field) or `:condition`, `:year`, `:month`, `:quarter`, or a literal's;
  `agg`, the aggregate it is or holds, or false; for a record, `id`, its id, and `text`,
  the SQL it sorts and compares by; `name` and `label`; the `field` it reads; and the
  `parents` and `values` it uses. A mistake throws `{:report_error, %Error{}}`, which
  App.Report.Compiler catches.
  """

  import Ecto.Query, only: [where: 3]

  alias App.Model.Activity
  alias App.Report.Catalog
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.LocalTime
  alias App.Report.Query
  alias App.Report.Range
  alias App.Report.SQL
  alias App.Report.Value

  @aggregates ~w(count sum avg min max)
  @date_parts ~w(year month quarter days_since)
  @numbers [:number, :hours, :km]
  @matches [:contains, :starts_with, :ends_with, :like]
  @flip %{eq: :eq, ne: :ne, lt: :gt, gt: :lt, le: :ge, ge: :le}

  @contact ~w(email phone address emergency_contact primary_emergency_contact
              secondary_emergency_contact coordinate)

  @doc "The aggregate functions."
  def aggregates, do: @aggregates

  @doc "An expression for `ast`."
  def compile({:field, path, args, line}, st),
    do: field(Enum.map(path, &String.downcase/1), args, line, st)

  def compile({:literal, value, line}, _st), do: literal(value, line)

  def compile({:value, name, line}, _st),
    do: fail(line, "Compare :#{name} with a field, such as year(started_at) = :#{name}.")

  def compile({:range, name, _n, line}, _st),
    do: fail(line, "Compare a date with #{name}, such as started_at = #{name}.")

  def compile({:call, name, distinct?, args, line}, st), do: call(name, distinct?, args, line, st)

  def compile({:not, inner, line}, st) do
    e = condition(inner, st)
    uses(new(["NOT (", e.sql, ")"], e.params, :condition, line), e)
  end

  def compile({:op, op, left, right, line}, st) when op in [:and, :or] do
    l = condition(left, st)
    r = condition(right, st)
    word = if op == :and, do: " AND ", else: " OR "
    uses(new(["(", l.sql, word, r.sql, ")"], l.params ++ r.params, :condition, line), [l, r])
  end

  def compile({:op, op, left, right, line}, st), do: compare(op, left, right, line, st)
  def compile({:is_null, inner, negated?, line}, st), do: null(compile(inner, st), negated?, line)

  def compile({:in, inner, items, negated?, line}, st),
    do: in_list(compile(inner, st), items, negated?, line, st)

  def compile({kind, inner, items, line}, st) when kind in [:includes, :excludes],
    do: includes(kind, compile(inner, st), items, line, st)

  @doc "An expression that must be a condition, as `where` and `and` take."
  def condition(ast, st) do
    e = compile(ast, st)

    unless e.type in [:condition, :bool],
      do: fail(Query.line(ast), "Write a condition, such as #{example_condition(ast)}.")

    e
  end

  @doc "The SQL that selects and groups an expression: a record's id."
  def id_sql(%{id: {sql, params}}), do: {sql, params}
  def id_sql(e), do: {e.sql, e.params}

  @doc "The SQL that sorts and compares an expression: a record's text."
  def sort_sql(%{text: {sql, params}}), do: {sql, params}
  def sort_sql(e), do: {e.sql, e.params}

  @doc "Throws a mistake on `line`."
  def fail(line, message), do: throw({:report_error, Error.new(line, message)})

  defp example_condition({:field, path, _, _}), do: "#{Enum.join(path, ".")} = 'something'"
  defp example_condition(_ast), do: "published = true"

  defp new(sql, params, type, line, attrs \\ []) do
    Map.merge(
      %{
        sql: sql,
        params: params,
        type: type,
        line: line,
        agg: false,
        id: nil,
        text: nil,
        name: nil,
        label: nil,
        field: nil,
        parents: [],
        values: []
      },
      Map.new(attrs)
    )
  end

  defp uses(e, others) do
    others = List.wrap(others)

    %{
      e
      | agg: e.agg || Enum.find_value(others, false, & &1.agg),
        parents: Enum.uniq(e.parents ++ Enum.flat_map(others, & &1.parents)),
        values: e.values ++ Enum.flat_map(others, & &1.values)
    }
  end

  defp literal(value, line) when is_binary(value),
    do: new("?", [value], :text_literal, line, value: value)

  defp literal(value, line) when is_number(value),
    do: new("?", [value], :number_literal, line, value: value)

  defp literal(value, line) when is_boolean(value),
    do: new("?", [bool(value)], :bool_literal, line, value: value)

  defp literal(%Date{}, line),
    do: fail(line, "Compare a date with a date field, such as joined_at > date '2026-01-01'.")

  defp literal(nil, line), do: fail(line, "Write is null, or is not null, to look for a blank.")

  defp bool(true), do: 1
  defp bool(false), do: 0

  # Fields

  defp field([name], args, line, st), do: subject_field(st.subject, nil, name, args, line, st)

  defp field([parent, name], args, line, st) do
    case Map.fetch(st.subject.parents, parent) do
      {:ok, {subject_name, _fk}} ->
        subject_field(Catalog.subject(subject_name), parent, name, args, line, st)

      :error ->
        fail(line, no_field(st.subject, parent, Map.keys(st.subject.parents)))
    end
  end

  defp field(path, _args, line, _st),
    do:
      fail(line, "Write one dot at most, such as member.name: #{Enum.join(path, ".")} has more.")

  defp subject_field(subject, via, name, args, line, st) do
    subject
    |> Catalog.field(name)
    |> known(subject, via, name, line)
    |> field_expr(subject, via, args, line, st)
    |> Map.put(:name, if(via, do: "#{via}.#{name}", else: name))
  end

  defp known(nil, subject, _via, name, line) when name in @contact,
    do: fail(line, "Reports leave out contact details. #{subject.name} has no field #{name}.")

  defp known(nil, subject, via, name, line) do
    others = if via, do: [], else: Map.keys(subject.parents)
    fail(line, no_field(subject, name, others))
  end

  defp known(field, _subject, _via, _name, _line), do: field

  defp field_expr(%{args: [_ | _]} = field, _subject, via, args, line, st),
    do: roll_up(field, via, args, line, st)

  defp field_expr(field, _subject, via, [_ | _], line, _st) do
    name = if via, do: "#{via}.#{field.name}", else: field.name
    fail(line, "#{name} takes nothing in brackets. Write #{name}.")
  end

  defp field_expr(%{parent: parent}, _subject, via, _args, line, _st)
       when is_binary(parent) and is_binary(via),
       do:
         fail(
           line,
           "Write #{parent}.name from #{parent}'s own subject: reports reach one record away."
         )

  defp field_expr(%{parent: parent} = field, subject, nil, _args, line, _st)
       when is_binary(parent),
       do: parent_record(subject, field, line)

  defp field_expr(%{id_column: nil} = field, _subject, via, _args, line, _st) do
    sql = via |> SQL.table() |> SQL.column(field.column)
    new(sql, [], field.type, line, label: field.label, field: field, parents: List.wrap(via))
  end

  defp field_expr(field, _subject, via, _args, line, _st) do
    table = SQL.table(via)
    id = SQL.column(table, field.id_column)

    new(id, [], field.type, line,
      id: {id, []},
      text: {SQL.column(table, field.column), []},
      label: field.label,
      field: field,
      parents: List.wrap(via)
    )
  end

  # A parent, such as attendance's member: its id, and the text its own subject shows.
  defp parent_record(subject, field, line) do
    {subject_name, _fk} = Map.fetch!(subject.parents, field.parent)
    shown = subject_name |> Catalog.subject() |> Map.fetch!(:fields) |> Enum.find(& &1.id_column)
    table = SQL.table(field.parent)
    id = SQL.column(table, :id)

    new(id, [], field.type, line,
      id: {id, []},
      text: {SQL.column(table, shown.column), []},
      label: field.label,
      field: field,
      parents: [field.parent]
    )
  end

  defp roll_up(field, via, args, line, st) do
    if length(args) != length(field.args),
      do: fail(line, "Write #{field.name}(365): it takes a number of days.")

    days = Enum.map(args, &days(&1, field, line))
    table = SQL.table(via)
    {sql, params} = field.sql.(table, days, st.context)

    new(sql, Enum.map(params, &SQL.param/1), field.type, line,
      field: field,
      label: field.label,
      parents: List.wrap(via)
    )
  end

  defp days({:literal, n, _}, _field, _line) when is_integer(n) and n > 0, do: n

  defp days(_arg, field, line),
    do: fail(line, "Write #{field.name}(365): it takes a whole number of days.")

  defp no_field(subject, name, others) do
    names = subject |> Catalog.shown_fields() |> Enum.map(& &1.name) |> Enum.concat(others)

    case closest(name, names) do
      nil -> "#{subject.name} has no field #{name}. Its fields are listed beside the query."
      close -> "#{subject.name} has no field #{name}. Did you mean #{close}?"
    end
  end

  @doc "The name in `names` closest to `name`, or nil when none is close."
  # cspell:ignore jaro
  def closest(name, names) do
    names
    |> Enum.map(&{&1, String.jaro_distance(name, &1)})
    |> Enum.filter(fn {_name, score} -> score >= 0.75 end)
    |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0} end)
    |> elem(0)
  end

  # Functions

  defp call(name, distinct?, args, line, st) when name in @aggregates do
    if distinct? and name != "count",
      do: fail(line, "Write distinct only in count, such as count(distinct member).")

    arg =
      one_arg(args, line, "#{name} takes one field, such as #{name}(#{example_arg(name)}).", st)

    if arg.agg, do: fail(line, "Write one of count, sum, avg, min, or max at a time.")
    uses(aggregate(name, distinct?, arg, line), arg)
  end

  defp call(name, false, args, line, st) when name in @date_parts do
    arg = one_arg(args, line, "#{name} takes one date, such as #{name}(started_at).", st)

    unless arg.type == :date and arg.params == [],
      do: fail(line, "#{name} takes a date field, such as #{name}(started_at).")

    uses(date_part(name, LocalTime.sql(arg.sql, st.context.timezone), arg, line, st.context), arg)
  end

  defp call(name, false, args, line, st) when name in ["lower", "upper"] do
    arg = one_arg(args, line, "#{name} takes one text field, such as #{name}(title).", st)
    {sql, params} = sort_sql(arg)
    uses(new([String.upcase(name), "(", sql, ")"], params, :text, line, label: arg.label), arg)
  end

  defp call(name, true, _args, line, _st),
    do:
      fail(
        line,
        "Write distinct only in count, such as count(distinct member). #{name} cannot take it."
      )

  defp one_arg([arg], _line, _message, st), do: compile(arg, st)
  defp one_arg(_args, line, message, _st), do: fail(line, message)

  defp example_arg("count"), do: "id"
  defp example_arg(_name), do: "hours"

  defp aggregate("count", distinct?, arg, line) do
    {sql, params} = id_sql(arg)
    inner = if distinct?, do: ["DISTINCT ", sql], else: sql
    new(["COUNT(", inner, ")"], params, :number, line, agg: "count", label: "Count")
  end

  defp aggregate(name, _distinct?, %{type: type} = arg, line)
       when name in ["sum", "avg"] and type in [:bool | @numbers] do
    type = if type == :bool, do: :number, else: type
    label = if name == "sum", do: arg.label, else: "Average #{String.downcase(arg.label)}"
    new([String.upcase(name), "(", arg.sql, ")"], arg.params, type, line, agg: name, label: label)
  end

  defp aggregate(name, _distinct?, %{type: type} = arg, line)
       when name in ["min", "max"] and type in [:date, :text, :year, :month | @numbers] do
    new([String.upcase(name), "(", arg.sql, ")"], arg.params, type, line,
      agg: name,
      label: min_max_label(name, type, arg.label)
    )
  end

  defp aggregate(name, _distinct?, arg, line),
    do: fail(line, "#{name} adds up numbers and hours. #{arg.name} is #{type_text(arg.type)}.")

  defp date_part("year", local, _arg, line, _context),
    do: new(["CAST(strftime('%Y', ", local, ") AS INTEGER)"], [], :year, line, label: "Year")

  defp date_part("month", local, _arg, line, _context),
    do: new(["CAST(strftime('%m', ", local, ") AS INTEGER)"], [], :month, line, label: "Month")

  defp date_part("quarter", local, _arg, line, _context),
    do:
      new(["((CAST(strftime('%m', ", local, ") AS INTEGER) + 2) / 3)"], [], :quarter, line,
        label: "Quarter"
      )

  defp date_part("days_since", local, arg, line, context) do
    new(
      ["CAST(julianday(?) - julianday(date(", local, ")) AS INTEGER)"],
      [Date.to_iso8601(context.today)],
      :number,
      line,
      label: "Days since #{String.downcase(arg.label)}"
    )
  end

  defp min_max_label("min", :date, label), do: "First #{String.downcase(label)}"
  defp min_max_label("max", :date, label), do: "Last #{String.downcase(label)}"
  defp min_max_label("min", _type, label), do: "Lowest #{String.downcase(label)}"
  defp min_max_label("max", _type, label), do: "Highest #{String.downcase(label)}"

  defp type_text(type) when type in [:text, :choice], do: "text"
  defp type_text(:list), do: "a list"
  defp type_text(:date), do: "a date"
  defp type_text({:record, kind}) when kind in [:activity, :item], do: "an #{kind}"
  defp type_text({:record, kind}), do: "a #{kind}"
  defp type_text(_type), do: "not a number"

  # Comparisons

  defp compare(op, {:value, _, _} = left, right, line, st)
       when is_map_key(@flip, op) and elem(right, 0) != :value,
       do: compare(Map.fetch!(@flip, op), right, left, line, st)

  defp compare(op, {:literal, _, _} = left, {:field, _, _, _} = right, line, st)
       when is_map_key(@flip, op),
       do: compare(Map.fetch!(@flip, op), right, left, line, st)

  defp compare(op, left, right, line, st) do
    l = compile(left, st)
    if l.type == :condition, do: fail(line, "Write and or or between conditions.")
    compare_right(op, l, right, line, st)
  end

  defp compare_right(op, l, {:range, name, n, _}, line, st) when is_map_key(@flip, op) do
    unless l.type == :date,
      do: fail(line, "Compare #{name} with a date field, such as started_at = #{name}.")

    dates(op, l, Range.of(name, n, st.context), line)
  end

  defp compare_right(op, l, {:literal, %Date{} = date, _}, line, st) when is_map_key(@flip, op) do
    unless l.type == :date,
      do: fail(line, "Compare a date with a date field, such as joined_at > date '2026-01-01'.")

    dates(op, l, Range.day(date, st.context), line)
  end

  defp compare_right(_op, _l, {:literal, nil, _}, line, _st),
    do: fail(line, "Write is null, or is not null, to look for a blank.")

  defp compare_right(op, l, {:value, name, _}, line, st), do: compare_value(op, l, name, line, st)

  defp compare_right(op, l, right, line, st) when op in @matches,
    do: match(op, l, compile(right, st), line)

  defp compare_right(op, l, right, line, st),
    do: compare_sides(op, l, compile(right, st), line, st)

  # A value matched with contains, such as the search box's :q, is text whatever it
  # meets: compared with tags, it would otherwise be a menu of their titles.
  defp compare_value(op, l, name, line, st) when op in @matches do
    given = Map.get(st.given, name)
    value = %Value{name: name, label: Value.label(name), kind: :text, value: given || ""}
    r = new("?", [value.value], :value, line, value: value.value)
    %{match(op, l, r, line) | values: [value | l.values]}
  end

  defp compare_value(op, l, name, line, st) do
    value = value(name, l, st)
    r = new("?", [value_param(value, l)], :value, line, value: value.value)
    e = value_compare(value.kind, op, l, r, value, line, st)
    %{e | values: [value | e.values]}
  end

  defp value_compare(:date, op, l, _r, value, line, st) when is_map_key(@flip, op),
    do: dates(op, l, Range.day(value.value, st.context), line)

  defp value_compare(:date, _op, _l, _r, value, line, _st),
    do: fail(line, "Compare :#{value.name} with =, <, or >.")

  defp value_compare(_kind, op, l, r, _value, line, st), do: compare_sides(op, l, r, line, st)

  defp compare_sides(op, l, r, line, st) do
    {left_sql, left_params} = compared_sql(l)
    {right_sql, right_params} = right_param(l, r, line, st)
    sql = [left_sql, " ", op_sql(op), " ", right_sql, collate(l)]
    uses(new(sql, left_params ++ right_params, :condition, line), [l, r])
  end

  # The right side in the left side's terms: a choice by its label or value, yes or no as
  # 1 or 0, and hours as minutes.
  defp right_param(%{type: :choice} = l, %{type: :text_literal, value: text}, line, st),
    do: {"?", [choice_value(l, text, line, st)]}

  defp right_param(%{type: :bool}, %{type: :bool_literal, value: value}, _line, _st),
    do: {"?", [bool(value)]}

  defp right_param(%{type: :hours}, %{type: :number_literal, value: n}, _line, _st),
    do: {"?", [n * 60]}

  defp right_param(%{type: type} = l, %{type: :text_literal}, line, _st)
       when type in [:year, :month, :quarter, :bool, :date | @numbers],
       do: fail(line, "Compare #{l.name || "it"} with #{example_value(type)}, not text.")

  defp right_param(%{type: :list} = l, _r, line, _st),
    do:
      fail(
        line,
        "Use includes or excludes with #{l.name}, such as #{l.name} includes ('Callout')."
      )

  defp right_param(_l, r, _line, _st), do: {r.sql, r.params}

  defp example_value(:bool), do: "true or false"
  defp example_value(:date), do: "a date, such as date '2026-01-01'"
  defp example_value(_type), do: "a number"

  defp choice_value(l, text, line, st) do
    choices = l.field.choices.(st.context)
    lower = String.downcase(text)

    found =
      Enum.find(choices, fn {label, value} ->
        lower in [String.downcase(label), String.downcase(value)]
      end)

    case found do
      {_label, value} -> value
      nil -> fail(line, "#{l.name} is never '#{text}'. Use one of: #{choice_list(choices)}.")
    end
  end

  defp choice_list(choices), do: Enum.map_join(choices, ", ", &"'#{elem(&1, 0)}'")

  defp match(op, l, r, line) do
    unless text_like?(l) or l.type in [:choice, :list],
      do: fail(line, "Use #{op_sql(op)} with a text field, such as title contains 'river'.")

    unless r.type in [:text_literal, :value],
      do: fail(line, "Write text in quotes after #{op_sql(op)}, such as '#{op_example(op)}'.")

    {sql, params} = compared_sql(l)
    {match_sql, match_params} = list_match(l.type, op, sql, Map.get(r, :value) || "")
    uses(new(match_sql, params ++ match_params, :condition, line), [l, r])
  end

  # A list matches when one of its titles does, so a search can look in tags (#784).
  defp list_match(:list, op, sql, value) do
    {inner, params} = match_sql(op, "value", value)
    {["EXISTS (SELECT 1 FROM json_each(", sql, ") WHERE ", inner, ")"], params}
  end

  defp list_match(_type, op, sql, value), do: match_sql(op, sql, value)

  defp match_sql(:contains, sql, value), do: {["instr(lower(", sql, "), lower(?)) > 0"], [value]}
  defp match_sql(:like, sql, value), do: {[sql, " LIKE ?"], [value]}

  defp match_sql(:starts_with, sql, value),
    do: {[sql, " LIKE ? ESCAPE '\\'"], [escape(value) <> "%"]}

  defp match_sql(:ends_with, sql, value),
    do: {[sql, " LIKE ? ESCAPE '\\'"], ["%" <> escape(value)]}

  defp op_example(:like), do: "%river%"
  defp op_example(_op), do: "river"

  defp escape(text),
    do:
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

  defp op_sql(:eq), do: "="
  defp op_sql(:ne), do: "!="
  defp op_sql(:lt), do: "<"
  defp op_sql(:gt), do: ">"
  defp op_sql(:le), do: "<="
  defp op_sql(:ge), do: ">="
  defp op_sql(:contains), do: "contains"
  defp op_sql(:starts_with), do: "starts with"
  defp op_sql(:ends_with), do: "ends with"
  defp op_sql(:like), do: "like"

  defp text_like?(%{type: type}), do: type == :text or match?({:record, _}, type)
  defp collate(e), do: if(text_like?(e), do: " COLLATE NOCASE", else: "")

  # A record compares by its text, such as a member by name.
  defp compared_sql(%{type: {:record, _}} = e), do: sort_sql(e)
  defp compared_sql(e), do: {e.sql, e.params}

  defp null(e, negated?, line) do
    {sql, params} = id_sql(e)
    {sql, params} = null_sql(e.type, negated?, sql, params)
    uses(new(sql, params, :condition, line), e)
  end

  # An empty list is a blank too.
  defp null_sql(:list, true, sql, params),
    do: {["(", sql, " IS NOT NULL AND json_array_length(", sql, ") > 0)"], params ++ params}

  defp null_sql(:list, false, sql, params),
    do: {["(", sql, " IS NULL OR json_array_length(", sql, ") = 0)"], params ++ params}

  defp null_sql(_type, true, sql, params), do: {[sql, " IS NOT NULL"], params}
  defp null_sql(_type, false, sql, params), do: {[sql, " IS NULL"], params}

  defp in_list(e, items, negated?, line, st) do
    {sql, params} = compared_sql(e)
    {item_params, values} = items(items, e, st)
    word = if negated?, do: " NOT IN (", else: " IN ("
    sql = [sql, collate(e), word, marks(item_params), ")"]
    uses(new(sql, params ++ item_params, :condition, line, values: values), e)
  end

  defp includes(kind, %{type: :list} = e, items, line, st) do
    {item_params, values} = items(items, e, st)
    word = if kind == :includes, do: "EXISTS", else: "NOT EXISTS"

    sql = [
      word,
      " (SELECT 1 FROM json_each(",
      e.sql,
      ") WHERE value COLLATE NOCASE IN (",
      marks(item_params),
      "))"
    ]

    uses(new(sql, e.params ++ item_params, :condition, line, values: values), e)
  end

  defp includes(kind, e, _items, line, _st),
    do:
      fail(
        line,
        "Use #{kind} with a list field, such as groups or tags. For #{e.name}, write in (...)."
      )

  defp marks(params), do: Enum.map_join(params, ", ", fn _ -> "?" end)

  defp items(items, e, st) do
    {params, values} = items |> Enum.map(&item(&1, e, st)) |> Enum.unzip()
    {params, Enum.concat(values)}
  end

  defp item({:literal, text, line}, %{type: :choice} = e, st) when is_binary(text),
    do: {choice_value(e, text, line, st), []}

  defp item({:literal, value, _line}, _e, _st) when is_binary(value) or is_number(value),
    do: {value, []}

  defp item({:value, name, _line}, e, st) do
    value = value(name, e, st)
    {value_param(value, e), [value]}
  end

  defp item(other, _e, _st),
    do: fail(Query.line(other), "Write each item as text in quotes, such as ('Callout', 'Rope').")

  # A date range compared with `op`: `=` is inside it, `<` before it, `>` after it.
  defp dates(op, l, {start, finish}, line) do
    {sql, params} = date_sql(op, l.sql, l.params, SQL.param(start), SQL.param(finish))
    uses(new(sql, params, :condition, line), l)
  end

  defp date_sql(:eq, sql, p, start, finish),
    do: {["(", sql, " >= ? AND ", sql, " < ?)"], Enum.concat([p, [start], p, [finish]])}

  defp date_sql(:ne, sql, p, start, finish),
    do: {["(", sql, " < ? OR ", sql, " >= ?)"], Enum.concat([p, [start], p, [finish]])}

  defp date_sql(:lt, sql, p, start, _finish), do: {[sql, " < ?"], Enum.concat(p, [start])}
  defp date_sql(:ge, sql, p, start, _finish), do: {[sql, " >= ?"], Enum.concat(p, [start])}
  defp date_sql(:gt, sql, p, _start, finish), do: {[sql, " >= ?"], Enum.concat(p, [finish])}
  defp date_sql(:le, sql, p, _start, finish), do: {[sql, " < ?"], Enum.concat(p, [finish])}

  # Values

  defp value(name, l, st) do
    {kind, choices} = value_kind(l, st.context)
    picked = Value.pick(kind, Map.get(st.given, name), choices, st.context.today)
    %Value{name: name, label: Value.label(name), kind: kind, choices: choices, value: picked}
  end

  defp value_kind(%{type: :year}, context), do: {:year, year_choices(context)}
  defp value_kind(%{type: :date}, _context), do: {:date, []}
  defp value_kind(%{type: :bool}, _context), do: {:choice, [{"Yes", "true"}, {"No", "false"}]}

  defp value_kind(%{type: type}, _context) when type in [:month, :quarter | @numbers],
    do: {:number, []}

  defp value_kind(%{type: type, field: field}, context) when type in [:choice, :list],
    do: {:choice, field.choices.(context)}

  defp value_kind(_e, _context), do: {:text, []}

  defp value_param(%Value{kind: :choice, choices: [{"Yes", "true"}, _]} = value, _l),
    do: if(value.value == "true", do: 1, else: 0)

  defp value_param(%Value{value: value}, %{type: :hours}) when is_number(value), do: value * 60
  defp value_param(%Value{value: value}, _l), do: value

  # The years with activities, newest first, and this year.
  defp year_choices(%Context{team: team, today: today, timezone: timezone}) do
    query = where(Activity, [a], a.team_id == ^team.id and is_nil(a.deleted_at))

    [today.year | Activity.years(query, timezone)]
    |> Enum.uniq()
    |> Enum.sort(:desc)
    |> Enum.map(&{Integer.to_string(&1), Integer.to_string(&1)})
  end
end

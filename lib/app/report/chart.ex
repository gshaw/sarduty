defmodule App.Report.Chart do
  @moduledoc """
  Experiment (charts): the proposed `chart` clause, read beside the engine rather than in
  its parser, so the engine's own tests are untouched.

  A spec is a report's text with one more line at the end:

      chart stat | columns | lines | bars | calendar | week   [compare year] [cumulative]

  `run/4` runs the report, and for `compare year` runs it again with the query's own
  dates a year back (ranges, NOW, and each year it picks), while its fields' rules, such
  as Attended and Not retired, stay as of now. A stat over a series takes its number
  from the query without its axis. `shape/4` turns the rows into what
  `Web.Components.Chart` draws. It writes no SQL beyond the stat's total.

  The x axis is the report's first column, or its first two when they are year and
  month. A time axis is filled with zeros between the bounds the `where` gives the field
  it buckets (a range, `<= NOW`, `months_since(…) < n`, `year(…) = :year`), or between
  the first and last row when it gives none. Series are the pivot's columns, or the
  number columns after the axis.
  """

  alias App.Report
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Parser
  alias App.Report.Picks
  alias App.Report.Query
  alias App.Report.Range
  alias App.Report.Runner
  alias App.Report.Value
  alias Service.Format

  defstruct [:name, :text, :kind, compare: nil, cumulative: false]

  @kinds %{
    "stat" => :stat,
    "columns" => :columns,
    "lines" => :lines,
    "bars" => :bars,
    "calendar" => :calendar,
    "week" => :week
  }

  # A pivot on an activity's kind keeps the kinds' colours (tokens.css).
  @kind_series %{"incident" => :incident, "exercise" => :exercise, "event" => :event}

  def read(path), do: path |> File.read!() |> parse(Path.basename(path, ".report"))

  @doc "The spec when `text` ends in a chart line, or nil."
  def find(text) when is_binary(text) do
    case last_words(text) do
      ["chart", kind | _] when is_map_key(@kinds, kind) -> parse(text)
      _other -> nil
    end
  end

  def find(_text), do: nil

  @doc "The report's text without its chart line."
  def query_text(text), do: if(spec = find(text), do: spec.text, else: text)

  defp last_words(text),
    do: text |> String.trim_trailing() |> String.split("\n") |> List.last() |> String.split()

  def parse(text, name \\ nil) do
    lines = text |> String.trim_trailing() |> String.split("\n")
    rest = Enum.drop(lines, -1)

    case last_words(text) do
      ["chart", kind | options] when is_map_key(@kinds, kind) ->
        %__MODULE__{
          name: name,
          text: Enum.join(rest, "\n") <> "\n",
          kind: Map.fetch!(@kinds, kind),
          compare: if(compare_year?(options), do: :year),
          cumulative: "cumulative" in options
        }

      _other ->
        raise "#{name}: end the spec with a chart line, such as chart columns"
    end
  end

  defp compare_year?(["compare", "year" | _rest]), do: true
  defp compare_year?([_option | rest]), do: compare_year?(rest)
  defp compare_year?([]), do: false

  @doc "Runs the spec: `{:ok, %{result, before, data, before_data}}` or `{:error, error}`."
  def run(%__MODULE__{} = spec, team, given \\ %{}, now \\ DateTime.utc_now()),
    do: run_with(spec, Context.new(team, now), given)

  @doc "run/4 on a context built once, as a page of charts would share it."
  def run_with(%__MODULE__{} = spec, %Context{} = context, given \\ %{}) do
    before_context = year_back(context)

    with {:ok, result} <- Report.run_with(context, spec.text, given),
         {:ok, before} <- earlier(spec, before_context, given, result) do
      {:ok,
       %{
         result: result,
         before: before,
         data: data(spec, result, context, given),
         before_data: before && data(spec, before, before_context, before_given(result, given))
       }}
    end
  end

  # A stat over a series takes its number from the query without its axis, so a
  # distinct count over the year is not the sum of its months' distinct counts.
  defp data(spec, result, context, given) do
    data = shape(spec, result, context, given)

    if spec.kind == :stat and axis(result),
      do: %{data | value: total(spec, context, given)},
      else: data
  end

  # The query's own dates a year back; its fields' rules, such as Attended, as of now.
  defp year_back(context) do
    dates_now = DateTime.shift(context.now, year: -1)

    %{
      context
      | dates_now: dates_now,
        dates_today: Service.Period.today(dates_now, context.timezone)
    }
  end

  defp earlier(%{compare: nil}, _context, _given, _result), do: {:ok, nil}

  defp earlier(%{compare: :year} = spec, before_context, given, result),
    do: Report.run_with(before_context, spec.text, before_given(result, given))

  # Each year value one less: a report for 2025 compares with 2024.
  defp before_given(result, given) do
    Enum.reduce(result.values, given, fn
      %Value{kind: :year} = value, acc ->
        Map.put(acc, value.name, "#{String.to_integer("#{Value.param(value)}") - 1}")

      _value, acc ->
        acc
    end)
  end

  defp total(spec, context, given) do
    {:ok, query} = Parser.parse(spec.text)
    grouped? = fn expr -> Enum.any?(query.group_by, &Query.same?(&1, expr)) end

    query = %{
      query
      | select: Enum.reject(query.select, grouped?),
        labels: Enum.reject(query.labels, fn {expr, _text} -> grouped?.(expr) end),
        group_by: [],
        order_by: []
    }

    {:ok, plan} = Compiler.compile(query, context, given)
    {:ok, result} = Runner.run(plan, context.timezone, context.repo)
    first_number(result)
  end

  ## Shapes

  def shape(%{kind: :stat} = spec, result, context, given) do
    case axis(result) do
      nil ->
        %{value: first_number(result), spark: nil, note: note(result)}

      axis ->
        series = series(result, axis, spec, context, given)
        values = series |> hd() |> Map.fetch!(:values)
        %{value: Enum.sum(values), spark: spark_values(values, hd(series).type), note: nil}
    end
  end

  def shape(%{kind: :columns} = spec, result, context, given) do
    axis = axis(result) || {:category, 0}
    series = series(result, axis, spec, context, given)
    buckets = buckets(result, axis, spec, context, given)

    columns =
      buckets
      |> Enum.with_index()
      |> Enum.map(fn {bucket, i} -> column(bucket, i, axis, series) end)

    %{columns: columns, series: Enum.map(series, &{&1.key, &1.label})}
  end

  def shape(%{kind: :lines} = spec, result, context, given) do
    axis = axis(result) || {:category, 0}
    series = series(result, axis, spec, context, given)
    buckets = buckets(result, axis, spec, context, given)

    %{
      labels: Enum.map(buckets, &short_label(&1, axis)),
      series: Enum.map(series, &%{key: &1.key, label: &1.label, values: &1.values})
    }
  end

  def shape(%{kind: :calendar} = spec, result, context, given) do
    {:day, i} = axis(result) || raise "a calendar takes date(…) first"
    by_day = Map.new(result.rows, &{Enum.at(&1, i), Enum.at(&1, i + 1) || 0})
    days = buckets(result, {:day, i}, spec, context, given)
    %{days: Enum.map(days, &{&1, Map.get(by_day, &1, 0)})}
  end

  def shape(%{kind: :week}, result, _context, _given) do
    counts = Map.new(result.rows, fn [day, hour, n | _] -> {{day, hour}, n} end)
    %{rows: for(day <- 1..7, do: for(hour <- 0..23, do: Map.get(counts, {day, hour}, 0)))}
  end

  def shape(%{kind: :bars}, result, _context, _given) do
    [label_column | _] = result.columns
    value_index = Enum.find_index(result.columns, &(&1.type in [:number, :hours, :km]))
    value_column = Enum.at(result.columns, value_index)

    rows =
      Enum.map(result.rows, fn row ->
        value = Enum.at(row, value_index) || 0

        %{
          label: hd(row),
          label_type: label_column.type,
          value: value,
          text: text(value, value_column)
        }
      end)

    %{rows: rows}
  end

  defp column(bucket, i, axis, series) do
    values = for s <- series, into: %{}, do: {s.key, column_value(Enum.at(s.values, i), s.type)}
    %{label: short_label(bucket, axis), values: values, tip: tip(bucket, axis, series, i)}
  end

  ## The axis

  # The first column, or the first two when they are year and month.
  def axis(%{columns: [%{type: :year}, %{type: :month} | _]}), do: {:year_month, 0}
  def axis(%{columns: [%{type: :day} | _]}), do: {:day, 0}
  def axis(%{columns: [%{type: :month} | _]}), do: {:month, 0}
  def axis(%{columns: [%{type: :year} | _]}), do: {:year, 0}
  def axis(%{columns: [%{type: :quarter} | _]}), do: {:quarter, 0}
  def axis(%{columns: [%{type: :hour} | _]}), do: {:hour, 0}
  def axis(%{columns: [%{type: :weekday} | _]}), do: {:weekday, 0}
  def axis(_result), do: nil

  defp axis_width({:year_month, _}), do: 2
  defp axis_width(_axis), do: 1

  defp key(row, {:year_month, i}), do: {Enum.at(row, i), Enum.at(row, i + 1)}
  defp key(row, {_kind, i}), do: Enum.at(row, i)

  # Every bucket the where allows, oldest first; a category axis keeps the rows' order.
  defp buckets(result, {:category, i}, _spec, _context, _given),
    do: Enum.map(result.rows, &Enum.at(&1, i))

  defp buckets(result, axis, spec, context, given) do
    keys = Enum.map(result.rows, &key(&1, axis))

    case bounds(spec, context, given) do
      {first, last} -> fill(axis, first, last)
      nil when keys == [] -> []
      nil -> fill_between(axis, Enum.min(keys), Enum.max(keys))
    end
  end

  defp fill({:year_month, _}, first, last) do
    first
    |> Date.beginning_of_month()
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.compare(&1, last) != :gt))
    |> Enum.map(&{&1.year, &1.month})
  end

  defp fill({:day, _}, first, last), do: first |> Date.range(last) |> Enum.to_list()
  defp fill({:month, _}, first, last), do: Enum.to_list(first.month..last.month//1)
  defp fill({:year, _}, first, last), do: Enum.to_list(first.year..last.year//1)

  defp fill({:quarter, _}, first, last),
    do: Enum.to_list(div(first.month + 2, 3)..div(last.month + 2, 3)//1)

  defp fill({:hour, _}, _first, _last), do: Enum.to_list(0..23)
  defp fill({:weekday, _}, _first, _last), do: Enum.to_list(1..7)

  defp fill_between({:year_month, _}, {y1, m1}, {y2, m2}),
    do: fill({:year_month, 0}, Date.new!(y1, m1, 1), Date.new!(y2, m2, 1))

  defp fill_between({:day, _}, first, last), do: first |> Date.range(last) |> Enum.to_list()

  defp fill_between({kind, _}, first, last) when kind in [:month, :year, :quarter],
    do: Enum.to_list(first..last//1)

  defp fill_between({:hour, _}, _first, _last), do: Enum.to_list(0..23)
  defp fill_between({:weekday, _}, _first, _last), do: Enum.to_list(1..7)

  ## Bounds from the where

  @doc """
  The first and last local dates the where allows for the field the axis buckets, or
  nil: `field = RANGE`, `field <= NOW`, `months_since(field) < n`, `year(field) = n`.
  """
  def bounds(spec, context, given) do
    {:ok, query} = Parser.parse(spec.text)
    # A filter's pick adds its where, as the run's own query has it.
    picks = Picks.resolve(query, given, context.today)
    query = Picks.plain(query, picks)
    given = picks.given

    case {axis_field(query), query.where} do
      {nil, _} ->
        nil

      {_path, nil} ->
        nil

      {path, where} ->
        where
        |> conditions()
        |> Enum.reduce(nil, &narrow(&1, &2, path, context, given))
        |> local(context)
    end
  end

  defp axis_field(%{select: [{:call, _name, false, [{:field, path, [], _}], _} | _]}), do: path
  defp axis_field(_query), do: nil

  defp conditions({:op, :and, left, right, _}), do: conditions(left) ++ conditions(right)
  defp conditions(condition), do: [condition]

  defp narrow(
         {:op, :eq, {:field, path, [], _}, {:range, name, n, _}, _},
         acc,
         path,
         context,
         _given
       ),
       do: intersect(acc, Range.of(name, n, context))

  defp narrow(
         {:op, op, {:field, path, [], _}, {:range, "NOW", nil, _}, _},
         acc,
         path,
         context,
         _given
       )
       when op in [:le, :lt],
       do: intersect(acc, {nil, context.dates_now})

  defp narrow(
         {:op, op, {:call, "months_since", false, [{:field, path, [], _}], _}, {:literal, n, _},
          _},
         acc,
         path,
         context,
         _given
       )
       when op in [:lt, :le] do
    back = if op == :lt, do: n - 1, else: n
    first = context.dates_today |> Date.beginning_of_month() |> Date.shift(month: -back)
    intersect(acc, {Service.DayRange.start_of_day(first, context.timezone), nil})
  end

  defp narrow(
         {:op, :eq, {:call, "year", false, [{:field, path, [], _}], _}, right, _},
         acc,
         path,
         context,
         given
       ) do
    case year_of(right, given, context) do
      nil -> acc
      year -> intersect(acc, Range.year(year, context))
    end
  end

  defp narrow(_condition, acc, _path, _context, _given), do: acc

  defp year_of({:literal, n, _}, _given, _context) when is_integer(n), do: n

  defp year_of({:value, name, _}, given, context),
    do: given |> Map.get(name, "#{context.dates_today.year}") |> String.to_integer()

  defp year_of(_right, _given, _context), do: nil

  defp intersect(nil, range), do: range
  defp intersect({s1, f1}, {s2, f2}), do: {latest(s1, s2), earliest(f1, f2)}

  defp latest(nil, b), do: b
  defp latest(a, nil), do: a
  defp latest(a, b), do: if(DateTime.after?(a, b), do: a, else: b)

  defp earliest(nil, b), do: b
  defp earliest(a, nil), do: a
  defp earliest(a, b), do: if(DateTime.before?(a, b), do: a, else: b)

  # UTC bounds, the finish exclusive unless it is NOW, as local dates.
  defp local(nil, _context), do: nil
  defp local({nil, _finish}, _context), do: nil

  defp local({start, finish}, context) do
    finish = finish || context.dates_now
    last = if finish == context.dates_now, do: finish, else: DateTime.add(finish, -1)
    {to_date(start, context), to_date(last, context)}
  end

  defp to_date(datetime, context),
    do: datetime |> DateTime.shift_zone!(context.timezone) |> DateTime.to_date()

  ## Series

  # One series per pivot column, or per number column after the axis. A pivot on an
  # activity's kind keeps the kinds' colours; anything else is primary, then numbered.
  defp series(result, axis, spec, context, given) do
    buckets = buckets(result, axis, spec, context, given)
    by_key = Map.new(result.rows, &{key(&1, axis), &1})

    result
    |> number_columns(axis)
    |> Enum.with_index()
    |> Enum.map(fn {{column, i}, n} ->
      values = Enum.map(buckets, &cell(by_key[&1], i))
      values = if spec.cumulative, do: Enum.scan(values, &(&1 + &2)), else: values
      %{key: series_key(column, n), label: column.label, type: column.type, values: values}
    end)
  end

  # A bucket with no row is 0, so the axis keeps its place.
  defp cell(nil, _i), do: 0
  defp cell(row, i), do: Enum.at(row, i) || 0

  # The number columns after the axis, each with its index in the row, but a total.
  defp number_columns(result, axis) do
    result.columns
    |> Enum.with_index()
    |> Enum.drop(axis_width(axis))
    |> Enum.filter(fn {c, _i} -> c.type in [:number, :hours, :km] and c[:pivot] != :total end)
  end

  # The kinds' own colours, then primary and the numbered series (chart.css), in order.
  defp series_key(%{pivot: kind, pivot_type: :choice}, _n) when is_map_key(@kind_series, kind),
    do: Map.fetch!(@kind_series, kind)

  defp series_key(_column, 0), do: :primary
  defp series_key(_column, n), do: "c#{n}"

  # Columns of hours round, so an hour-long training still shows; a stat's line drops
  # the minutes, as both pages do today.
  defp column_value(minutes, :hours), do: round(minutes / 60)
  defp column_value(value, _type), do: value

  defp spark_values(values, :hours), do: Enum.map(values, &div(&1, 60))
  defp spark_values(values, _type), do: values

  defp first_number(%{rows: [row | _], columns: columns}) do
    i = Enum.find_index(columns, &(&1.type in [:number, :hours, :km]))
    Enum.at(row, i) || 0
  end

  defp first_number(_result), do: 0

  # A stat's second number, with its label: "1 joined this year".
  defp note(%{rows: [row | _], columns: columns}) do
    case columns
         |> Enum.with_index()
         |> Enum.filter(&(elem(&1, 0).type in [:number, :hours, :km])) do
      [_first, {column, i} | _] -> {Enum.at(row, i) || 0, column}
      _other -> nil
    end
  end

  defp note(_result), do: nil

  ## Labels

  defp short_label({_year, month}, {:year_month, _}), do: month |> month() |> Format.month_short()
  defp short_label(date, {:day, _}), do: Format.date_short(date)
  defp short_label(month, {:month, _}), do: month |> month() |> Format.month_short()
  defp short_label(value, {:quarter, _}), do: "Q#{value}"
  defp short_label(value, {:hour, _}), do: Runner.hour_text(value)
  defp short_label(value, {:weekday, _}), do: value |> Runner.weekday_name() |> String.slice(0, 3)
  defp short_label(value, _axis), do: to_string(value)

  defp long_label({year, month}, {:year_month, _}),
    do: month |> month(year) |> Format.month_year_long()

  defp long_label(value, axis), do: short_label(value, axis)

  defp month(month, year \\ 2000), do: Date.new!(year, month, 1)

  defp tip(bucket, axis, series, i) do
    lines =
      for s <- series, n = Enum.at(s.values, i), n > 0 do
        "#{s.label}: #{text(n, %{type: s.type})}"
      end

    Enum.join([long_label(bucket, axis) | lines], "\n")
  end

  defp text(value, %{type: :hours}), do: Format.duration(value)
  defp text(value, %{type: :km}), do: Format.km(value)
  defp text(value, _column), do: Format.number(value)
end

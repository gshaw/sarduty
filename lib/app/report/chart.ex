defmodule App.Report.Chart do
  @moduledoc """
  A report's chart (#826): the last clause, `chart stat | columns | lines | bars |
  calendar | week`, then `compare year` or `cumulative`. It draws the rows the report
  already shows, as the app's own charts (Web.Components.Chart) draw them. Pure but for
  running the query: no field, no SQL of its own beyond a stat's total.

  - **The axis** is the first column, or the first two when they're `year()` and
    `month()`, read as one month axis.
  - **The series** are the pivot's columns, or the number columns after the axis. A
    pivot on an activity's kind keeps the kinds' colours; anything else is primary, then
    5 fixed colours (chart.css).
  - **Every bucket the `where` allows is drawn**, with 0 for none: `field = RANGE`,
    `field <= NOW`, `months_since(field) < n`, and `year(field) = n` bound it, or the
    first and last row when nothing does.
  - **A stat's number is the query's own total**, run once more without its axis, since
    adding up months would count an activity twice when it has rows in two.
  - **`compare year`** runs the query again with its own dates a year back (ranges, NOW,
    `months_since`, and each year it picks), while fields' rules stay as of now.
  """

  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Query
  alias App.Report.Range
  alias App.Report.Runner
  alias App.Report.Value
  alias Service.Format

  @numbers [:number, :hours, :km]
  @kind_series %{"incident" => :incident, "exercise" => :exercise, "event" => :event}
  @series_keys [:primary, :c1, :c2, :c3, :c4, :c5]
  @max_series length(@series_keys)
  @max %{columns: 36, lines: 60, calendar: 366}

  @doc "The most of each a chart draws: columns, line points, calendar days, and series."
  def limits, do: Map.put(@max, :series, @max_series)

  @doc """
  `:ok` when the report's columns fit its chart, or `{:error, error}` naming what each
  kind takes.
  """
  def check(nil, _columns), do: :ok

  def check(%{kind: kind, line: line} = chart, columns) do
    with :ok <- check_options(chart),
         :ok <- check_columns(kind, columns) do
      :ok
    else
      {:error, message} -> {:error, Error.new(line, message)}
    end
  end

  defp check_options(%{compare_year: true, kind: kind}) when kind not in [:stat, :lines],
    do: {:error, "compare year works with chart stat or chart lines."}

  defp check_options(%{cumulative: true, kind: kind}) when kind not in [:stat, :columns, :lines],
    do: {:error, "cumulative works with chart stat, columns, or lines."}

  defp check_options(_chart), do: :ok

  defp check_columns(:calendar, [%{type: :day}, %{type: type} | _]) when type in @numbers,
    do: :ok

  defp check_columns(:calendar, _columns),
    do: {:error, "A calendar takes date(started_at) first, then a count."}

  defp check_columns(:week, [%{type: :weekday}, %{type: :hour}, %{type: type} | _])
       when type in @numbers,
       do: :ok

  defp check_columns(:week, _columns),
    do: {:error, "A week takes day_of_week(started_at), then hour(started_at), then a count."}

  defp check_columns(kind, columns) do
    if Enum.any?(columns, &(&1.type in @numbers)),
      do: :ok,
      else: {:error, "chart #{kind} draws numbers. Select a count, a sum, or a number field."}
  end

  @doc """
  Draws `plain`, the query with its picks, whose rows are `result`: `{:ok, chart}` or
  `{:error, error}`. A chart is `%{kind, data, before, hours?, label}`: `data` is what the
  kind's component takes, and `before` the same a year back, or nil.
  """
  def build(%Query{chart: chart} = plain, result, %Context{} = context, given) do
    with {:ok, data} <- data(chart, plain, result, context, given),
         {:ok, before} <- before(chart, plain, result, context, given) do
      {:ok,
       %{
         kind: chart.kind,
         data: data,
         before: before,
         hours?: Enum.any?(result.columns, &(&1.type == :hours)),
         label: label(result)
       }}
    else
      {:error, message} when is_binary(message) -> {:error, Error.new(chart.line, message)}
      error -> error
    end
  end

  defp data(chart, plain, result, context, given) do
    with {:ok, data} <- shape(chart, result, plain, context, given) do
      own_total(chart.kind == :stat and axis(result) != nil, data, plain, context, given)
    end
  end

  defp own_total(false, data, _plain, _context, _given), do: {:ok, data}

  defp own_total(true, data, plain, context, given) do
    with {:ok, value} <- total(plain, context, given), do: {:ok, %{data | value: value}}
  end

  defp before(%{compare_year: false}, _plain, _result, _context, _given), do: {:ok, nil}

  defp before(chart, plain, result, context, given) do
    context = Context.year_back(context)
    given = year_back(result, given)

    with {:ok, plan} <- Compiler.compile(%{plain | chart: nil}, context, given),
         {:ok, before} <- Runner.run(plan, context.timezone, context.repo) do
      data(chart, plain, before, context, given)
    end
  end

  # Each year picked one less: a report for 2026 compares with 2025.
  defp year_back(result, given) do
    Enum.reduce(result.values, given, fn
      %Value{kind: :year} = value, acc ->
        Map.put(
          acc,
          value.name,
          Integer.to_string(String.to_integer("#{Value.param(value)}") - 1)
        )

      _value, acc ->
        acc
    end)
  end

  # The query without its axis: one row, the stat's own number.
  defp total(plain, context, given) do
    grouped? = fn expr -> Enum.any?(plain.group_by, &Query.same?(&1, expr)) end

    query = %{
      plain
      | select: Enum.reject(plain.select, grouped?),
        labels: Enum.reject(plain.labels, fn {expr, _text} -> grouped?.(expr) end),
        formats: Enum.reject(plain.formats, fn {expr, _name} -> grouped?.(expr) end),
        group_by: [],
        order_by: [],
        pivot: [],
        totals: false,
        chart: nil
    }

    with {:ok, plan} <- Compiler.compile(query, context, given),
         {:ok, result} <- Runner.run(plan, context.timezone, context.repo) do
      {:ok, first_number(result)}
    end
  end

  ## Shapes

  defp shape(%{kind: :stat} = chart, result, plain, context, given) do
    case axis(result) do
      nil ->
        {:ok, %{value: first_number(result), spark: nil, note: note(result)}}

      axis ->
        with {:ok, buckets} <- buckets(result, axis, plain, context, given, :lines) do
          [first | _] = series(result, axis, buckets, chart)
          {:ok, %{value: Enum.sum(first.values), spark: first.values, note: nil}}
        end
    end
  end

  defp shape(%{kind: :columns} = chart, result, plain, context, given) do
    axis = axis(result) || {:category, 0}

    with {:ok, buckets} <- buckets(result, axis, plain, context, given, :columns),
         {:ok, series} <- capped_series(result, axis, buckets, chart) do
      columns =
        buckets
        |> Enum.with_index()
        |> Enum.map(fn {bucket, i} -> column(bucket, i, axis, series) end)

      {:ok, %{columns: columns, series: Enum.map(series, &{&1.key, &1.label})}}
    end
  end

  defp shape(%{kind: :lines} = chart, result, plain, context, given) do
    axis = axis(result) || {:category, 0}

    with {:ok, buckets} <- buckets(result, axis, plain, context, given, :lines),
         {:ok, series} <- capped_series(result, axis, buckets, chart) do
      {:ok,
       %{
         labels: Enum.map(buckets, &short_label(&1, axis)),
         series: Enum.map(series, &Map.take(&1, [:key, :label, :values, :type]))
       }}
    end
  end

  defp shape(%{kind: :calendar}, result, plain, context, given) do
    by_day = Map.new(result.rows, fn [day, n | _] -> {day, n || 0} end)

    with {:ok, days} <- buckets(result, {:day, 0}, plain, context, given, :calendar) do
      {:ok, %{days: Enum.map(days, &{&1, Map.get(by_day, &1, 0)})}}
    end
  end

  defp shape(%{kind: :week}, result, _plain, _context, _given) do
    counts = Map.new(result.rows, fn [day, hour, n | _] -> {{day, hour}, n || 0} end)
    {:ok, %{rows: for(day <- 1..7, do: for(hour <- 0..23, do: Map.get(counts, {day, hour}, 0)))}}
  end

  defp shape(%{kind: :bars}, result, _plain, _context, _given) do
    i = Enum.find_index(result.columns, &(&1.type in @numbers))
    value_column = Enum.at(result.columns, i)
    [label_column | _] = result.columns

    rows =
      Enum.map(result.rows, fn row ->
        value = Enum.at(row, i) || 0

        %{
          label: hd(row),
          label_column: label_column,
          value: value,
          text: text(value, value_column)
        }
      end)

    {:ok, %{rows: rows}}
  end

  defp column(bucket, i, axis, series) do
    values = for s <- series, into: %{}, do: {s.key, column_value(Enum.at(s.values, i), s.type)}
    %{label: short_label(bucket, axis), values: values, tip: tip(bucket, axis, series, i)}
  end

  ## The axis

  @doc "The axis the rows give: `{kind, index}` for a time axis, or nil."
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
  defp buckets(result, {:category, i}, _plain, _context, _given, kind),
    do: result.rows |> Enum.map(&Enum.at(&1, i)) |> capped(kind)

  defp buckets(result, axis, plain, context, given, kind) do
    keys = Enum.map(result.rows, &key(&1, axis))

    buckets =
      case bounds(plain, context, given) do
        {first, last} -> fill(axis, first, last)
        nil when keys == [] -> []
        nil -> fill_between(axis, Enum.min(keys), Enum.max(keys))
      end

    capped(buckets, kind)
  end

  defp capped(buckets, kind) do
    max = Map.fetch!(@max, kind)

    if length(buckets) > max,
      do:
        {:error,
         "chart #{kind} draws at most #{Format.number(max)}. Narrow the where, such as months_since(started_at) < 12."},
      else: {:ok, buckets}
  end

  defp fill({:year_month, _}, first, last) do
    first
    |> Date.beginning_of_month()
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.compare(&1, last) != :gt))
    |> Enum.map(&{&1.year, &1.month})
  end

  defp fill({:day, _}, first, last), do: first |> Date.range(last) |> Enum.to_list()

  defp fill({:month, _}, first, last) when first.year == last.year,
    do: Enum.to_list(first.month..last.month//1)

  defp fill({:month, _}, _first, _last), do: Enum.to_list(1..12)
  defp fill({:year, _}, first, last), do: Enum.to_list(first.year..last.year//1)

  defp fill({:quarter, _}, first, last) when first.year == last.year,
    do: Enum.to_list(div(first.month + 2, 3)..div(last.month + 2, 3)//1)

  defp fill({:quarter, _}, _first, _last), do: Enum.to_list(1..4)
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

  # The first and last local dates the where allows for the field the axis buckets, or
  # nil when it doesn't bound it.
  defp bounds(%Query{where: nil}, _context, _given), do: nil

  defp bounds(%Query{} = plain, context, given) do
    case axis_field(plain) do
      nil ->
        nil

      path ->
        plain.where
        |> conditions()
        |> Enum.reduce(nil, &narrow(&1, &2, path, context, given))
        |> local(context)
    end
  end

  defp axis_field(%{select: [{:call, _name, false, [{:field, path, [], _}], _} | _]}), do: path
  defp axis_field(_query), do: nil

  defp conditions({:op, :and, left, right, _}), do: conditions(left) ++ conditions(right)
  defp conditions(condition), do: [condition]

  defp narrow({:op, :eq, {:field, path, [], _}, {:range, name, n, _}, _}, acc, path, context, _),
    do: intersect(acc, Range.of(name, n, context))

  defp narrow({:op, op, {:field, path, [], _}, {:range, "NOW", nil, _}, _}, acc, path, context, _)
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
       when op in [:lt, :le] and is_integer(n) do
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

  defp year_of({:value, name, _}, given, _context) do
    case Integer.parse("#{Map.get(given, name)}") do
      {year, ""} -> year
      _other -> nil
    end
  end

  defp year_of(_right, _given, _context), do: nil

  defp intersect(nil, range), do: range
  defp intersect({s1, f1}, {s2, f2}), do: {latest(s1, s2), earliest(f1, f2)}

  defp latest(nil, b), do: b
  defp latest(a, nil), do: a
  defp latest(a, b), do: if(DateTime.after?(a, b), do: a, else: b)

  defp earliest(nil, b), do: b
  defp earliest(a, nil), do: a
  defp earliest(a, b), do: if(DateTime.before?(a, b), do: a, else: b)

  # UTC bounds as local dates: the finish is exclusive unless it is NOW, and a range with
  # no finish ends now.
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

  defp capped_series(result, axis, buckets, chart) do
    series = series(result, axis, buckets, chart)

    if length(series) > @max_series,
      do:
        {:error,
         "A chart draws at most #{@max_series} series. Pivot on a field with fewer values."},
      else: {:ok, series}
  end

  # One series per pivot column, or per number column after the axis, but a total.
  defp series(result, axis, buckets, chart) do
    by_key = Map.new(result.rows, &{key(&1, axis), &1})

    result
    |> series_columns(axis)
    |> Enum.with_index()
    |> Enum.map(fn {{column, i}, n} ->
      values = values(buckets, by_key, i, chart.cumulative)
      %{key: series_key(column, n), label: column.label || "", type: column.type, values: values}
    end)
  end

  # The number columns after the axis, each with its index in a row, but a total.
  defp series_columns(result, axis) do
    result.columns
    |> Enum.with_index()
    |> Enum.drop(axis_width(axis))
    |> Enum.filter(fn {c, _i} -> c.type in @numbers and c[:pivot] != :total end)
  end

  defp values(buckets, by_key, i, cumulative?) do
    values = Enum.map(buckets, &cell(by_key[&1], i))
    if cumulative?, do: Enum.scan(values, &(&1 + &2)), else: values
  end

  # A bucket with no row is 0, so the axis keeps its place.
  defp cell(nil, _i), do: 0
  defp cell(row, i), do: Enum.at(row, i) || 0

  # The kinds' own colours, then primary and the numbered colours, in order.
  defp series_key(%{pivot: kind, pivot_type: :choice}, _n) when is_map_key(@kind_series, kind),
    do: Map.fetch!(@kind_series, kind)

  defp series_key(_column, n), do: Enum.at(@series_keys, n)

  # Hours round to whole hours in a column, so an hour-long training still shows.
  defp column_value(minutes, :hours), do: round(minutes / 60)
  defp column_value(value, _type), do: value

  defp first_number(%{rows: [row | _], columns: columns}) do
    i = Enum.find_index(columns, &(&1.type in @numbers))
    (i && Enum.at(row, i)) || 0
  end

  defp first_number(_result), do: 0

  # A stat's second number, with its column: "1 joined this year".
  defp note(%{rows: [row | _], columns: columns}) do
    case columns |> Enum.with_index() |> Enum.filter(&(elem(&1, 0).type in @numbers)) do
      [_first, {column, i} | _] -> {Enum.at(row, i) || 0, column}
      _other -> nil
    end
  end

  defp note(_result), do: nil

  # The first number column's label, a stat's own.
  defp label(%{columns: columns}) do
    case Enum.find(columns, &(&1.type in @numbers)) do
      nil -> nil
      column -> column.label
    end
  end

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

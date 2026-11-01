defmodule App.Report.Runner do
  @moduledoc """
  Runs a plan (App.Report.Compiler) and reads its rows back by type, then makes the
  pivot's columns and the total row in Elixir. A run stops after 2 seconds: SQLite is
  interrupted, and the report says to narrow it. Any other SQLite error is a bug in the
  SQL App.Report.Compiler wrote, so it is logged for Honeybadger.
  """

  alias App.Repo
  alias App.Report.Compiler
  alias App.Report.Error
  alias App.Report.Plan
  alias App.Report.Result
  alias App.Report.SQL
  alias Service.Format

  require Logger

  @timeout 2_000

  @doc "`{:ok, %Result{}}`, or `{:error, %Error{}}` when it takes too long or makes too many columns."
  def run(%Plan{} = plan, timezone) do
    case query(plan.sql, plan.params) do
      {:ok, %{rows: rows}} -> shape(plan, rows, timezone)
      {:error, error} -> {:error, error}
    end
  end

  @doc "The one number a count's SQL gives (App.Report.Compiler.count/3), or an error."
  def count({sql, params}) do
    case query(sql, params) do
      {:ok, %{rows: [[n]]}} -> {:ok, n}
      {:error, error} -> {:error, error}
    end
  end

  @doc "The numbers a counts' SQL gives (App.Report.Compiler.counts/4), in order, or an error."
  def counts({sql, params}) do
    case query(sql, params) do
      {:ok, %{rows: [ns]}} -> {:ok, ns}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  The values an each's SQL gives (App.Report.Compiler.values/3), decoded as `type`, with no
  blank: leaving it out here, not in SQL, reads each row's value once.
  """
  def values({sql, params}, type) do
    case query(sql, params) do
      {:ok, %{rows: rows}} -> {:ok, for([v] <- rows, v != nil, do: decode(v, type))}
      {:error, error} -> {:error, error}
    end
  end

  defp query(sql, params) do
    case Repo.query(sql, Enum.map(params, &SQL.param/1), timeout: @timeout) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, failed(reason)}
    end
  end

  defp failed(%Exqlite.Error{message: "interrupted"}),
    do: Error.new(nil, "Narrow the report with where: it took longer than 2 seconds.")

  defp failed(reason) do
    Logger.error("Report could not run: #{Exception.message(reason)}")
    Error.new(nil, "This report could not run. Try again, or change its query.")
  end

  defp shape(%Plan{pivot: nil} = plan, rows, _timezone) do
    types = Enum.map(plan.columns, & &1.type)
    {rows, more?} = rows |> Enum.map(&decode_row(&1, types)) |> cap(plan.max_rows)
    columns = Enum.map(plan.columns, &Map.put(&1, :pivot, nil))
    {:ok, result(plan, columns, rows, more?)}
  end

  defp shape(%Plan{} = plan, rows, timezone) do
    rows = Enum.map(rows, &pivot_row(&1, plan))
    pivots = rows |> Enum.map(& &1.pivot) |> Enum.uniq() |> sort_pivots(plan.pivot)
    count = length(pivots)
    max = Compiler.max_pivot()

    if count > max do
      message =
        "Narrow the pivot with where: it makes #{count} columns, and a report shows at most #{max}."

      {:error, Error.new(nil, message)}
    else
      {:ok, pivot(plan, rows, pivots, timezone)}
    end
  end

  # A row with a pivot: its shown cells, its group keys, its pivot value, and its order
  # values, in that order.
  defp pivot_row(row, plan) do
    {cells, rest} = Enum.split(row, length(plan.columns))
    {keys, [pivot | order]} = Enum.split(rest, plan.keys)
    cells = decode_row(cells, Enum.map(plan.columns, & &1.type))
    %{cells: cells, keys: keys, pivot: decode(pivot, plan.pivot.type), order: order}
  end

  defp pivot(plan, rows, pivots, timezone) do
    {aggregates, plain} =
      plan.columns |> Enum.with_index() |> Enum.split_with(fn {c, _i} -> c.agg end)

    layout = %{aggregates: aggregates, plain: plain, pivots: pivots, totals: plan.totals}
    columns = pivot_columns(layout, plan.pivot, timezone)

    {rows, more?} =
      rows
      |> groups()
      |> Enum.map(&pivot_cells(&1, layout, plan.order))
      |> sort_rows(plan.order)
      |> Enum.map(&elem(&1, 0))
      |> Enum.drop(plan.offset || 0)
      |> take(plan.limit)
      |> cap(plan.max_rows)

    result(plan, columns, rows, more?)
  end

  defp take(rows, nil), do: rows
  defp take(rows, limit), do: Enum.take(rows, limit)

  defp pivot_columns(layout, pivot, timezone) do
    one? = length(layout.aggregates) == 1
    plain = Enum.map(layout.plain, fn {column, _i} -> Map.put(column, :pivot, nil) end)

    shown =
      for p <- layout.pivots, {column, _i} <- layout.aggregates do
        label = pivot_label(p, pivot, timezone)
        label = if one? or is_nil(label), do: label, else: "#{label} #{column.label}"
        Map.merge(column, %{label: label, pivot: p, pivot_type: pivot.type})
      end

    totals =
      if layout.totals,
        do: Enum.map(layout.aggregates, fn {column, _i} -> total_column(column, one?) end),
        else: []

    Enum.concat([plain, shown, totals])
  end

  defp total_column(column, true), do: Map.merge(column, %{label: "Total", pivot: :total})

  defp total_column(column, false),
    do: Map.merge(column, %{label: "Total #{String.downcase(column.label)}", pivot: :total})

  # The rows of each group, in the order the query gave them.
  defp groups(rows) do
    {order, by_keys} = Enum.reduce(rows, {[], %{}}, &add_to_group/2)
    order |> Enum.reverse() |> Enum.map(&(by_keys |> Map.fetch!(&1) |> Enum.reverse()))
  end

  defp add_to_group(row, {order, by_keys}) do
    order = if Map.has_key?(by_keys, row.keys), do: order, else: [row.keys | order]
    {order, Map.update(by_keys, row.keys, [row], &[row | &1])}
  end

  defp pivot_cells(group, layout, order) do
    by_pivot = Map.new(group, &{&1.pivot, &1.cells})
    plain = Enum.map(layout.plain, fn {_column, i} -> Enum.at(hd(group).cells, i) end)
    shown = for p <- layout.pivots, {_column, i} <- layout.aggregates, do: cell(by_pivot, p, i)
    totals = if layout.totals, do: Enum.map(layout.aggregates, &group_total(group, &1)), else: []
    {Enum.concat([plain, shown, totals]), order_keys(order, group)}
  end

  defp cell(by_pivot, p, i) do
    case Map.fetch(by_pivot, p) do
      {:ok, cells} -> Enum.at(cells, i)
      :error -> nil
    end
  end

  defp group_total(group, {column, i}),
    do: group |> Enum.map(&Enum.at(&1.cells, i)) |> combine(column.total)

  defp order_keys(order, group) do
    order
    |> Enum.with_index()
    |> Enum.map(fn {{how, _dir}, i} -> order_key(Enum.map(group, &Enum.at(&1.order, i)), how) end)
  end

  defp order_key(values, :first), do: hd(values)
  defp order_key(values, :avg), do: combine(values, :sum)
  defp order_key(values, how), do: combine(values, how)

  defp sort_rows(rows, []), do: rows

  defp sort_rows(rows, order) do
    dirs = Enum.map(order, &elem(&1, 1))
    Enum.sort(rows, fn {_a, ka}, {_b, kb} -> before?(Enum.zip([ka, kb, dirs])) end)
  end

  defp before?([]), do: true
  defp before?([{a, a, _dir} | rest]), do: before?(rest)
  defp before?([{nil, _b, {_dir, :nulls_first}} | _rest]), do: true
  defp before?([{_a, nil, {_dir, :nulls_first}} | _rest]), do: false
  defp before?([{nil, _b, {_dir, :nulls_last}} | _rest]), do: false
  defp before?([{_a, nil, {_dir, :nulls_last}} | _rest]), do: true
  defp before?([{a, b, {dir, _nulls}} | rest]), do: before?([{a, b, dir} | rest])
  defp before?([{a, b, :asc} | _rest]), do: lesser?(a, b)
  defp before?([{a, b, :desc} | _rest]), do: lesser?(b, a)

  # Blanks first going up, as SQLite sorts them.
  defp lesser?(nil, _b), do: true
  defp lesser?(_a, nil), do: false

  defp lesser?(a, b) when is_binary(a) and is_binary(b),
    do: String.downcase(a) < String.downcase(b)

  defp lesser?(a, b), do: a < b

  # A choice's columns come in the choices' order: Attended, Signed up, Absent.
  defp sort_pivots(values, %{choices: choices}) when is_list(choices) do
    order = Enum.map(choices, &elem(&1, 1))
    last = length(order)
    Enum.sort_by(values, fn v -> {is_nil(v), Enum.find_index(order, &(&1 == v)) || last, v} end)
  end

  defp sort_pivots(values, _pivot), do: Enum.sort_by(values, &{is_nil(&1), &1})

  defp pivot_label(nil, _pivot, _timezone), do: "None"

  defp pivot_label(value, %{choices: choices}, _timezone) when is_list(choices),
    do: choice_label(choices, value)

  defp pivot_label(true, _pivot, _timezone), do: "Yes"
  defp pivot_label(false, _pivot, _timezone), do: "No"
  defp pivot_label(value, %{type: :month}, _timezone), do: month_name(value)
  defp pivot_label(value, %{type: :quarter}, _timezone), do: "Q#{value}"
  defp pivot_label(value, %{type: :year}, _timezone), do: Integer.to_string(value)
  defp pivot_label(value, %{type: :date}, timezone), do: Format.date_short(value, timezone)
  defp pivot_label(_value, %{type: {:record, _}}, _timezone), do: nil

  defp pivot_label(value, %{type: type}, _timezone) when type in [:number, :km],
    do: Format.number(value)

  defp pivot_label(value, _pivot, _timezone), do: to_string(value)

  @doc "A choice's label from its value, or the value when it is not one of them."
  def choice_label(choices, value) do
    case Enum.find(choices, &(elem(&1, 1) == value)) do
      {label, _value} -> label
      nil -> value
    end
  end

  @doc "A month's name from its number: 1 is January."
  def month_name(n) when is_integer(n) and n in 1..12,
    do: 2000 |> Date.new!(n, 1) |> Calendar.strftime("%B")

  def month_name(_n), do: ""

  defp result(plan, columns, rows, more?) do
    %Result{
      columns: columns,
      rows: rows,
      totals: if(plan.totals, do: totals(columns, rows)),
      more?: more?,
      values: plan.values,
      subject: plan.subject.name
    }
  end

  defp totals(columns, rows) do
    columns
    |> Enum.with_index()
    |> Enum.map(fn {column, i} -> column_total(column, rows, i) end)
  end

  defp column_total(%{total: nil}, _rows, _i), do: nil

  defp column_total(column, rows, i),
    do: rows |> Enum.map(&Enum.at(&1, i)) |> combine(column.total)

  defp combine(values, how) do
    case Enum.reject(values, &is_nil/1) do
      [] -> nil
      values -> combine_values(values, how)
    end
  end

  defp combine_values(values, :sum), do: Enum.sum(values)
  defp combine_values(values, :min), do: Enum.min(values)
  defp combine_values(values, :max), do: Enum.max(values)
  defp combine_values(_values, _how), do: nil

  defp cap(rows, nil), do: {rows, false}
  defp cap(rows, max) when length(rows) > max, do: {Enum.take(rows, max), true}
  defp cap(rows, _max), do: {rows, false}

  defp decode_row(row, types),
    do: row |> Enum.zip(types) |> Enum.map(fn {v, t} -> decode(v, t) end)

  defp decode(nil, _type), do: nil
  defp decode(value, :bool), do: value in [1, true]
  defp decode(value, :date) when is_binary(value), do: datetime(value)

  defp decode(value, :list) when is_binary(value),
    do: value |> Jason.decode!() |> Enum.reject(&is_nil/1) |> Enum.sort_by(&String.downcase/1)

  defp decode(value, _type), do: value

  defp datetime(text) do
    case DateTime.from_iso8601(text) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _reason} -> naive_datetime(text)
    end
  end

  defp naive_datetime(text) do
    text
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end
end

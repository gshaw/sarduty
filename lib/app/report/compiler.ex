defmodule App.Report.Compiler do
  @moduledoc """
  Checks a parsed query against the catalog and turns it into SQL (#768).

  Every name in a query is checked against App.Report.Catalog before anything runs, and
  a mistake names its line and the closest field (App.Report.Expr). The SQL reads the
  subject's source, a subquery already scoped to the team, joined to the sources of the
  parents it names. Names in the SQL come only from the catalog, and every value a query
  writes is a parameter.

  Text matches ignore case. Dates are the team's: `year(started_at)`, `TODAY`, and
  `date '2026-01-01'` are days in its time zone (App.Report.LocalTime).
  """

  import Ecto.Query, only: [from: 2, subquery: 1]

  alias App.Repo
  alias App.Report.Catalog
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Expr
  alias App.Report.Plan
  alias App.Report.Query
  alias App.Report.SQL
  alias App.Report.Subject
  alias Service.Format

  @max_rows 5_000
  @max_pivot 12

  @doc "The most rows a report shows."
  def max_rows, do: @max_rows

  @doc "The most columns a pivot makes."
  def max_pivot, do: @max_pivot

  @doc """
  `{:ok, %Plan{}}`, or `{:error, %Error{}}` for the first mistake. `given` holds the
  picked values by name, as text; a value not given gets its default (App.Report.Value).
  """
  def compile(%Query{} = query, %Context{} = context, given \\ %{}) do
    case Catalog.subject(query.from) do
      nil -> {:error, Error.new(query.from_line, unknown_subject(query.from))}
      subject -> plan(query, %{subject: subject, context: context, given: given})
    end
  catch
    {:report_error, %Error{} = error} -> {:error, error}
  end

  defp unknown_subject(name) do
    case Expr.closest(name, Catalog.names()) do
      nil -> "There is no subject #{name}. Use one of: #{Enum.join(Catalog.names(), ", ")}."
      close -> "There is no subject #{name}. Did you mean #{close}?"
    end
  end

  defp plan(query, st) do
    parts = %{
      select: Enum.map(query.select, &Expr.compile(&1, st)),
      where: query.where && Expr.condition(query.where, st),
      group: Enum.map(query.group_by, &Expr.compile(&1, st)),
      pivot: Enum.map(query.pivot, &Expr.compile(&1, st)),
      order: Enum.map(query.order_by, fn {ast, dir} -> {Expr.compile(ast, st), dir} end)
    }

    check(query, parts)
    {:ok, build(query, parts, st)}
  end

  # Checks

  defp check(query, parts) do
    query.select |> Enum.zip(parts.select) |> Enum.each(&check_shown/1)
    check_where(query.where, parts.where)
    check_pivot(query, parts.select)
    if grouped?(query, parts), do: check_group(query, parts)
    check_limit(query.limit)
    labels(query)
  end

  defp grouped?(query, parts),
    do: query.group_by != [] or query.pivot != [] or Enum.any?(parts.select, & &1.agg)

  # A report shows values, never a bare condition: `select published = true` is a
  # mistake for `select published`.
  defp check_shown({ast, %{type: :condition}}),
    do:
      fail(Query.line(ast), "Show a field, not a condition: move #{Query.text(ast)} into where.")

  defp check_shown(_shown), do: :ok

  defp check_where(_ast, nil), do: :ok
  defp check_where(_ast, %{agg: false}), do: :ok

  defp check_where(ast, _e),
    do:
      fail(
        Query.line(ast),
        "Take count, sum, avg, min, and max out of where: it picks rows before they are counted."
      )

  defp check_group(query, parts) do
    query.group_by |> Enum.zip(parts.group) |> Enum.each(&check_group_by/1)

    query.select
    |> Enum.zip(parts.select)
    |> Enum.reject(fn {ast, e} -> e.agg != false or grouped_by?(ast, query.group_by) end)
    |> Enum.each(fn {ast, _e} ->
      text = Query.text(ast)
      fail(Query.line(ast), "Add #{text} to group by, or count it: count(#{text}).")
    end)
  end

  defp check_group_by({ast, %{agg: false}}), do: ast

  defp check_group_by({ast, _e}),
    do: fail(Query.line(ast), "Group by a field, not #{Query.text(ast)}.")

  # `member.name` is one value for each member, so it shows beside `group by member`.
  defp grouped_by?({:field, [parent, _name], [], _} = ast, group_by),
    do: Enum.any?(group_by, &(Query.same?(&1, ast) or match?({:field, [^parent], [], _}, &1)))

  defp grouped_by?(ast, group_by), do: Enum.any?(group_by, &Query.same?(&1, ast))

  defp check_pivot(%{pivot: []}, _select), do: :ok

  defp check_pivot(%{pivot: [ast | rest]} = query, select) do
    line = Query.line(ast)
    text = Query.text(ast)
    if rest != [], do: fail(line, "Pivot on one field: a report makes columns from one.")

    if match?({:call, name, _, _, _} when name in ["count", "sum", "avg", "min", "max"], ast),
      do: fail(line, "Pivot on a field, not #{text}.")

    unless Enum.any?(select, & &1.agg),
      do: fail(line, "Add a count or sum to select for the pivot to show, such as count(id).")

    if Enum.any?(query.select, &Query.same?(&1, ast)),
      do:
        fail(
          line,
          "Take #{text} out of select: the pivot makes a column for each of its values."
        )
  end

  defp check_limit(n) when is_integer(n) and n > @max_rows,
    do: fail(nil, "Write a limit of #{Format.number(@max_rows)} or fewer.")

  defp check_limit(_n), do: :ok

  defp labels(query) do
    Enum.map(query.labels, fn {ast, text} ->
      unless Enum.any?(query.select, &Query.same?(&1, ast)),
        do: fail(Query.line(ast), "Add #{Query.text(ast)} to select, or take its label out.")

      {Query.strip(ast), text}
    end)
  end

  # The plan

  defp build(query, parts, st) do
    pivot? = parts.pivot != []
    used = used(parts)
    {sql, params} = sql(query, parts, st, used)
    labels = labels(query)

    %Plan{
      subject: st.subject,
      sql: sql,
      params: params,
      columns: query.select |> Enum.zip(parts.select) |> Enum.map(&column(&1, labels, st)),
      values: used |> Enum.flat_map(& &1.values) |> Enum.uniq_by(& &1.name),
      totals: query.totals,
      max_rows: if(query.limit && !pivot?, do: nil, else: @max_rows)
    }
    |> with_pivot(query, parts, st)
  end

  # With a pivot, the order and limit wait for the pivot's columns.
  defp sql(query, parts, st, used) do
    pivot? = parts.pivot != []
    parents = used |> Enum.flat_map(& &1.parents) |> Enum.uniq()
    where = parts.where && SQL.join([{" WHERE ", []}, {parts.where.sql, parts.where.params}])

    SQL.join([
      {"SELECT ", []},
      select_list(parts, pivot?),
      from_sql(st.subject, parents, st.context),
      where,
      grouped?(query, parts) && group_by(parts.group ++ parts.pivot),
      !pivot? && order_by(parts.order),
      !pivot? && limit_offset(query)
    ])
  end

  defp used(parts) do
    orders = Enum.map(parts.order, &elem(&1, 0))
    List.flatten([parts.select, List.wrap(parts.where), parts.group, parts.pivot, orders])
  end

  defp with_pivot(plan, _query, %{pivot: []}, _st), do: plan

  defp with_pivot(plan, query, parts, st) do
    %{
      plan
      | keys: length(parts.group),
        pivot: %{type: hd(parts.pivot).type, choices: choices(hd(parts.pivot), st)},
        order: Enum.map(parts.order, fn {e, dir} -> {combine(e), dir} end),
        limit: query.limit,
        offset: query.offset
    }
  end

  defp column({ast, e}, labels, st) do
    key = Query.strip(ast)
    label = Enum.find_value(labels, e.label, fn {k, text} -> if k == key, do: text end)
    %{label: label, type: e.type, agg: e.agg, total: total(e), choices: choices(e, st)}
  end

  # How a total row adds up a column: counts, sums, and plain numbers add up.
  defp total(%{agg: "min", type: type}) when type in [:number, :hours, :km], do: :min
  defp total(%{agg: "max", type: type}) when type in [:number, :hours, :km], do: :max
  defp total(%{agg: "avg"}), do: nil
  defp total(%{type: type}) when type in [:number, :hours, :km], do: :sum
  defp total(_e), do: nil

  defp combine(%{agg: agg}) when agg in ["count", "sum"], do: :sum
  defp combine(%{agg: "min"}), do: :min
  defp combine(%{agg: "max"}), do: :max
  defp combine(%{agg: "avg"}), do: :avg
  defp combine(_e), do: :first

  # A choice shows its label, incident as Incident: `[{label, value}]` in the choices' order.
  defp choices(%{type: :choice, field: %{choices: choices}}, st) when is_function(choices),
    do: choices.(st.context)

  defp choices(_e, _st), do: nil

  # SQL

  defp select_list(parts, pivot?) do
    shown = Enum.with_index(parts.select, fn e, i -> SQL.as(Expr.id_sql(e), "c#{i}") end)
    SQL.join(shown ++ if(pivot?, do: hidden(parts), else: []), ", ")
  end

  # With a pivot, the group keys, the pivot, and the order follow the shown columns.
  defp hidden(parts) do
    Enum.concat([
      Enum.with_index(parts.group, fn e, i -> SQL.as(Expr.id_sql(e), "g#{i}") end),
      [SQL.as(Expr.id_sql(hd(parts.pivot)), "p0")],
      Enum.with_index(parts.order, fn {e, _dir}, i -> SQL.as(Expr.sort_sql(e), "o#{i}") end)
    ])
  end

  defp from_sql(subject, parents, context) do
    {sql, params} = source(subject, context)
    joins = Enum.map(parents, &parent_join(subject, &1, context))
    SQL.join([{[" FROM (", sql, ") AS \"s\""], params} | joins])
  end

  defp parent_join(subject, parent, context) do
    {subject_name, fk} = Map.fetch!(subject.parents, parent)
    {sql, params} = subject_name |> Catalog.subject() |> source(context)
    table = SQL.table(parent)
    {[" LEFT JOIN (", sql, ") AS ", table, " ON ", table, ".\"id\" = \"s\".\"#{fk}\""], params}
  end

  # The source's columns by name, wrapped so each keeps its name in SQL.
  defp source(%Subject{source: source}, context) do
    query = from(s in subquery(source.(context)), select: s)
    {sql, params} = Repo.to_sql(:all, query)
    {sql, Enum.map(params, &SQL.param/1)}
  end

  defp group_by(es),
    do: SQL.join([{" GROUP BY ", []}, SQL.join(Enum.map(es, &Expr.id_sql/1), ", ")])

  defp order_by([]), do: nil

  defp order_by(order) do
    items = Enum.map(order, fn {e, dir} -> SQL.join([Expr.sort_sql(e), {direction(dir), []}]) end)
    SQL.join([{" ORDER BY ", []}, SQL.join(items, ", ")])
  end

  defp direction(:asc), do: " ASC"
  defp direction(:desc), do: " DESC"

  # One more row than a report shows, to tell when there are more.
  defp limit_offset(query),
    do: {" LIMIT ? OFFSET ?", [query.limit || @max_rows + 1, query.offset || 0]}

  defp fail(line, message), do: Expr.fail(line, message)
end

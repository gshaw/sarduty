defmodule App.Report.Query do
  @moduledoc """
  A parsed report query (App.Report.Parser). Expressions are tuples whose last element
  is their line:

  - `{:field, path, args, line}`: a field, `["member", "name"]` for `member.name`, with
    the arguments a roll-up field takes, such as `not_seen(365)`
  - `{:call, name, distinct?, args, line}`: a function, such as `sum(hours)`
  - `{:literal, value, line}`: a string, number, `true`, `false`, `null`, or a
    `Date` from `date '2026-01-01'`
  - `{:range, name, n, line}`: a date range, such as `LAST_N_DAYS:365` (n nil when it
    takes none)
  - `{:value, name, line}`: a value picked when the report runs, `:year`
  - `{:op, op, left, right, line}`: `:eq :ne :lt :gt :le :ge :and :or :contains
    :starts_with :ends_with :like`
  - `{:not, expr, line}`, `{:is_null, expr, negated?, line}`,
    `{:in, expr, items, negated?, line}`, `{:includes, expr, items, line}`, and
    `{:excludes, expr, items, line}`

  `order_by` holds `{expr, :asc | :desc}` and `labels` holds `{expr, text}`.
  """

  defstruct select: [],
            from: nil,
            from_line: 1,
            where: nil,
            group_by: [],
            pivot: [],
            order_by: [],
            limit: nil,
            offset: nil,
            labels: [],
            totals: false

  @doc "The line an expression is on."
  def line(expr) when is_tuple(expr), do: elem(expr, tuple_size(expr) - 1)

  @doc "The query's text for an expression, as a column's default name and in errors."
  def text({:field, path, [], _line}), do: Enum.join(path, ".")

  def text({:field, path, args, _line}),
    do: "#{Enum.join(path, ".")}(#{Enum.map_join(args, ", ", &text/1)})"

  def text({:call, name, true, args, _line}),
    do: "#{name}(distinct #{Enum.map_join(args, ", ", &text/1)})"

  def text({:call, name, false, args, _line}),
    do: "#{name}(#{Enum.map_join(args, ", ", &text/1)})"

  def text({:literal, value, _line}) when is_binary(value), do: "'#{value}'"
  def text({:literal, %Date{} = date, _line}), do: "date '#{Date.to_iso8601(date)}'"
  def text({:literal, nil, _line}), do: "null"
  def text({:literal, value, _line}), do: to_string(value)
  def text({:range, name, nil, _line}), do: name
  def text({:range, name, n, _line}), do: "#{name}:#{n}"
  def text({:value, name, _line}), do: ":#{name}"
  def text({:not, expr, _line}), do: "not #{text(expr)}"
  def text({:is_null, expr, false, _line}), do: "#{text(expr)} is null"
  def text({:is_null, expr, true, _line}), do: "#{text(expr)} is not null"
  def text({:op, :and, left, right, _line}), do: "#{in_and(left)} and #{in_and(right)}"
  def text({:op, op, left, right, _line}), do: "#{text(left)} #{op_text(op)} #{text(right)}"

  def text({:in, expr, items, negated?, _line}),
    do:
      "#{text(expr)} #{if negated?, do: "not in", else: "in"} (#{Enum.map_join(items, ", ", &text/1)})"

  def text({kind, expr, items, _line}) when kind in [:includes, :excludes],
    do: "#{text(expr)} #{kind} (#{Enum.map_join(items, ", ", &text/1)})"

  defp in_and({:op, :or, _, _, _} = expr), do: "(#{text(expr)})"
  defp in_and(expr), do: text(expr)

  defp op_text(:eq), do: "="
  defp op_text(:ne), do: "!="
  defp op_text(:lt), do: "<"
  defp op_text(:gt), do: ">"
  defp op_text(:le), do: "<="
  defp op_text(:ge), do: ">="
  defp op_text(:starts_with), do: "starts with"
  defp op_text(:ends_with), do: "ends with"
  defp op_text(op), do: to_string(op)

  @doc "Whether two expressions are the same, whatever their lines."
  def same?(a, b), do: strip(a) == strip(b)

  @doc "An expression with its lines taken out, to compare or use as a key."
  def strip(expr) when is_tuple(expr) do
    expr
    |> Tuple.delete_at(tuple_size(expr) - 1)
    |> Tuple.to_list()
    |> Enum.map(&strip/1)
    |> List.to_tuple()
  end

  def strip(list) when is_list(list), do: Enum.map(list, &strip/1)
  def strip(other), do: other
end

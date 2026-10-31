defmodule App.Report.Plan do
  @moduledoc """
  A checked query, ready to run (App.Report.Compiler): its SQL and parameters, and what
  App.Report.Runner needs to read the rows back.

  - `columns`: one per select item, `%{label, type, agg, total, choices}`; `total` is how
    a total row adds it up (`:sum`, `:min`, `:max`, or nil)
  - `keys`: with a pivot, how many hidden group columns follow the select ones
  - `pivot`: nil, or `%{type, choices}` for the pivot column after the keys
  - `order`: with a pivot, `[{combine, direction}]` for the hidden order columns last
  - `limit` and `offset`: applied after the pivot; without one, in SQL
  - `max_rows`: rows past it are left out, and the result says so
  """

  defstruct [
    :subject,
    :sql,
    :pivot,
    :limit,
    :offset,
    :max_rows,
    params: [],
    columns: [],
    keys: 0,
    order: [],
    values: [],
    totals: false
  ]
end

defmodule App.Report.Result do
  @moduledoc """
  A report's rows, as App.Report.Runner reads them back.

  - `columns`: `%{label, type, choices, total, pivot}`: `pivot` is the pivot value a
    column shows, or nil, and `pivot_type` its type
  - `rows`: a list of values per row, in the columns' order. A record is its id; a date
    a `DateTime`; hours are minutes; a list is its titles.
  - `totals`: the total row, nil without `totals`; a column that does not add up is nil
  - `more?`: whether rows past the most a report shows were left out
  - `values`: the values picked to run it (App.Report.Value)
  """

  defstruct columns: [], rows: [], totals: nil, more?: false, values: [], subject: nil
end

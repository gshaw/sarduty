defmodule App.Report.View do
  @moduledoc """
  A report run as a page (#784): its rows, and the controls its page's clauses draw.

  - `result`: the rows shown (App.Report.Result)
  - `total`: how many rows there are across pages
  - `page`: an `App.Page` when the report has `page`, or nil
  - `search?`: whether it has a search box, and `q` what it searches for
  - `switch`: nil, or `%{name, label, picked, tiles}`, each tile `%{value, label, count}`
    with All first unless it's `required`
  - `filters`: `%{name, label, picked, default, more, options}`, `options` as
    `[{label, value}]` with All first unless it's `required`
  - `sorts`: by column index, the header's `[{arrow, sort}]`, the first what a click on it
    picks; `sort` is the rows' sort
  - `values`: the query's other `:name` values (App.Report.Value), each a menu of its own
  - `params`: the picks as the URL writes them, and `defaults`, what each control starts
    on, so a URL leaves them out
  """

  defstruct [
    :result,
    :page,
    :sort,
    total: 0,
    search?: false,
    q: "",
    switch: nil,
    filters: [],
    sorts: %{},
    values: [],
    params: %{},
    defaults: %{}
  ]
end

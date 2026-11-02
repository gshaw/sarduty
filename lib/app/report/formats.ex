defmodule App.Report.Formats do
  @moduledoc """
  How a report column can look (#804). Each field draws its own cell, the first format
  for its type; `format started_at as date_time` picks another. Pure. The CSV keeps the
  values as they are, for a spreadsheet.
  """

  @dates [
    {"date", "Sep 28, 2026"},
    {"date_long", "September 28, 2026"},
    {"date_time", "Sep 28, 2026, 19:00"},
    {"month", "Sep 2026"},
    {"time", "19:00"},
    {"days_ago", "12 days ago"}
  ]

  @hours [{"duration", "212h 30m"}, {"hours", "212.5"}]
  @records [{"link", "The record's name, a link to its page."}, {"text", "The name alone."}]
  @markers [{"marker", "The kind's coloured square and its name."}, {"text", "The name alone."}]

  @doc """
  The formats a column can take, each `{name, what it shows}`, its own first. A column is
  a map with `type` and `cell`, as App.Report.Compiler makes it.
  """
  def all(%{cell: :activity_kind}), do: @markers
  def all(%{type: {:record, _kind}}), do: @records
  def all(%{type: :date}), do: @dates
  def all(%{type: :hours}), do: @hours
  def all(_column), do: []

  @doc "Every type's formats, for the language page: `[{type, formats}]`."
  def by_type,
    do: [
      {"date", @dates},
      {"hours", @hours},
      {"a record's link", @records},
      {"an activity's kind", @markers}
    ]

  @doc "The format a column draws with when the query picks none, or nil."
  def default(column) do
    case all(column) do
      [{name, _shows} | _] -> name
      [] -> nil
    end
  end

  @doc "The format's name when `column` can take it, or nil."
  def find(column, name),
    do: column |> all() |> Enum.find_value(fn {n, _shows} -> if n == name, do: n end)
end

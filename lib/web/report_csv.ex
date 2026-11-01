defmodule Web.ReportCSV do
  @moduledoc """
  A report's rows as CSV (#768): the same rows and columns as its page, unformatted, for a
  spreadsheet or an agent. A record is its name, a date the team's day as 2026-03-01,
  hours a decimal, a choice its label, and a list its titles split by semicolons.
  """

  alias App.Report.Result
  alias App.Report.Runner
  alias Web.Components.ReportTable

  @doc "The CSV text for `result`, with a header row, and a Total row when it has one."
  def build(%Result{} = result, records, timezone) do
    header = Enum.map(result.columns, &safe(ReportTable.label(&1, records) || ""))
    rows = Enum.map(result.rows, &row(&1, result.columns, records, timezone))
    totals = if result.totals, do: [total_row(result, records, timezone)], else: []

    [header | rows]
    |> Enum.concat(totals)
    |> Enum.map_join("", &line/1)
  end

  defp total_row(result, records, timezone) do
    [first | rest] = row(result.totals, result.columns, records, timezone)
    [if(first == "", do: "Total", else: first) | rest]
  end

  defp row(cells, columns, records, timezone) do
    cells
    |> Enum.zip(columns)
    |> Enum.map(fn {value, column} -> text(value, column, records, timezone) end)
  end

  defp text(nil, _column, _records, _timezone), do: ""

  defp text(id, %{type: {:record, kind}}, records, _timezone),
    do: records |> Map.get(kind, %{}) |> Map.get(id) |> record_text() |> safe()

  defp text(value, %{type: :date}, _records, timezone),
    do: value |> DateTime.shift_zone!(timezone) |> DateTime.to_date() |> Date.to_iso8601()

  defp text(minutes, %{type: :hours}, _records, _timezone),
    do: :erlang.float_to_binary(minutes / 60, decimals: 2)

  defp text(value, %{type: :bool}, _records, _timezone), do: to_string(value)
  defp text(value, %{type: :list}, _records, _timezone), do: value |> Enum.join("; ") |> safe()

  defp text(value, %{type: :choice, choices: choices}, _records, _timezone),
    do: choices |> List.wrap() |> Runner.choice_label(value) |> safe()

  defp text(value, %{type: :month}, _records, _timezone), do: Runner.month_name(value)
  defp text(value, _column, _records, _timezone) when is_binary(value), do: safe(value)
  defp text(value, _column, _records, _timezone), do: to_string(value)

  defp record_text(nil), do: ""
  defp record_text(%{name: name}), do: name
  defp record_text(%{title: title}), do: title

  defp line(cells), do: Enum.map_join(cells, ",", &field/1) <> "\r\n"

  # Text that starts like a formula gets a quote mark first, so a spreadsheet shows it as
  # text rather than running it.
  defp safe(text) do
    if String.starts_with?(text, ["=", "+", "-", "@"]), do: "'" <> text, else: text
  end

  # A cell with a comma, quote, or line break goes in quotes, its quotes doubled.
  defp field(text) do
    if String.contains?(text, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(text, "\"", "\"\"") <> "\"",
      else: text
  end
end

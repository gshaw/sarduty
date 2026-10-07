defmodule App.MCP.Output do
  @moduledoc "Formats values for MCP tool output. Pure."

  @doc "A stored time as ISO 8601 in the team's time zone, with its offset, or nil."
  def datetime(nil, _timezone), do: nil

  def datetime(%DateTime{} = datetime, timezone),
    do: datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_iso8601()

  def datetime(%NaiveDateTime{} = naive, timezone),
    do: naive |> DateTime.from_naive!("Etc/UTC") |> datetime(timezone)

  @doc "Minutes as hours, to 2 decimals."
  def hours(minutes) when is_integer(minutes), do: Float.round(minutes / 60, 2)
end

defmodule App.MCP.Output do
  @moduledoc "Formats values for MCP tool output. Pure."

  alias App.Model.Activity

  @doc "A stored time as ISO 8601 in the team's time zone, with its offset, or nil."
  def datetime(nil, _timezone), do: nil

  def datetime(%DateTime{} = datetime, timezone),
    do: datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_iso8601()

  def datetime(%NaiveDateTime{} = naive, timezone),
    do: naive |> DateTime.from_naive!("Etc/UTC") |> datetime(timezone)

  @doc "Minutes as hours, to 2 decimals."
  def hours(minutes) when is_integer(minutes), do: Float.round(minutes / 60, 2)

  @doc """
  Which tax credit hours an activity's tags count for: "primary", "secondary", "other"
  for the team's tag for no hours, or "none" with no hours tag. `hours_tags` is
  `Activity.hours_tags/1`.
  """
  def hours_kind(tags, hours_tags) do
    tags = tags || []

    case Activity.counts_as(tags, hours_tags) do
      nil -> if hours_tags[:other] && hours_tags[:other] in tags, do: "other", else: "none"
      kind -> Atom.to_string(kind)
    end
  end

  @doc "Whole minutes from `started_at` to `finished_at`, or nil when one is missing."
  def minutes(%DateTime{} = started_at, %DateTime{} = finished_at),
    do: max(DateTime.diff(finished_at, started_at, :minute), 0)

  def minutes(_started_at, _finished_at), do: nil
end

defmodule App.MCP.Args do
  @moduledoc "Reads MCP tool arguments. Pure: values in, values out."

  @doc """
  The `from` and `to` dates in `args`, `YYYY-MM-DD` and both included, as UTC bounds in
  the team's time zone: `{:ok, from, to, start, finish}`, where start is inclusive and
  finish exclusive. The bounds are UTC `NaiveDateTime`s, as Service.YearRange gives.
  """
  def date_range(args, timezone) do
    with {:ok, from} <- date(args, "from"),
         {:ok, to} <- date(args, "to"),
         :ok <- in_order(from, to) do
      {:ok, from, to, start_of_day(from, timezone), start_of_day(Date.add(to, 1), timezone)}
    end
  end

  defp date(args, key) do
    with value when is_binary(value) <- Map.get(args, key),
         {:ok, date} <- Date.from_iso8601(value) do
      {:ok, date}
    else
      _missing -> {:error, "Give #{key} as a date like 2026-01-31."}
    end
  end

  defp in_order(from, to) do
    if Date.after?(from, to),
      do: {:error, "Give a from date on or before the to date."},
      else: :ok
  end

  @doc "An optional string argument, trimmed, or nil when missing or blank."
  def optional_string(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: nil, else: String.trim(value)

      _other ->
        nil
    end
  end

  defp start_of_day(date, timezone) do
    datetime =
      case DateTime.new(date, ~T[00:00:00], timezone) do
        {:ok, datetime} -> datetime
        {:ambiguous, first, _second} -> first
        {:gap, _before, just_after} -> just_after
      end

    datetime |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_naive()
  end
end

defmodule App.Report.Value do
  @moduledoc """
  A value picked when a report runs, written `:name` in its query. Its kind comes from
  what it is compared with, so `year(started_at) = :year` is a year and `qualifications
  excludes (:qualification)` is one of the team's qualifications. Nothing declares it.

  - `kind`: `:year`, `:date`, `:number`, `:text`, or `:choice`
  - `choices`: `[{label, value}]` for a year or a choice, for its menu
  - `value`: what the report runs with, picked or the default
  """

  defstruct [:name, :label, :kind, :value, choices: []]

  @doc "The value as it rides in the URL and is saved with a report."
  def param(%__MODULE__{value: nil}), do: ""
  def param(%__MODULE__{value: %Date{} = date}), do: Date.to_iso8601(date)
  def param(%__MODULE__{value: value}), do: to_string(value)

  @doc "A name as the menu's label: `:start_date` is Start date."
  def label(name), do: name |> String.replace("_", " ") |> String.capitalize()

  @doc """
  The value of `kind` that `given`, text from a URL or a saved report, says; or the
  default: this year, January 1 of this year, the first choice, or blank.
  """
  def pick(kind, given, choices, today)

  def pick(:year, given, _choices, today) do
    case parse_integer(given) do
      year when is_integer(year) and year > 1900 and year < 2200 -> year
      _other -> today.year
    end
  end

  def pick(:date, given, _choices, today) do
    case given && Date.from_iso8601(given) do
      {:ok, date} -> date
      _other -> Date.new!(today.year, 1, 1)
    end
  end

  def pick(:number, given, _choices, _today), do: parse_number(given) || 0

  def pick(:choice, given, choices, _today) do
    values = Enum.map(choices, &elem(&1, 1))

    cond do
      given in values -> given
      values == [] -> nil
      true -> hd(values)
    end
  end

  def pick(:text, given, _choices, _today) when is_binary(given), do: given
  def pick(:text, _given, _choices, _today), do: ""

  defp parse_integer(text) when is_binary(text) do
    case Integer.parse(text) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp parse_integer(_other), do: nil

  # cspell:ignore trunc
  defp parse_number(text) when is_binary(text) do
    case Float.parse(text) do
      {n, ""} -> if n == trunc(n), do: trunc(n), else: n
      _other -> nil
    end
  end

  defp parse_number(_other), do: nil
end

defmodule Service.Format do
  @moduledoc """
    Useful functions for formatting data into strings.
  """

  @doc ~s(A count with its noun: "1 member", "1,204 members". `%d` marks the number.)
  def count(n, one: one, many: many) do
    template = if n == 1, do: one, else: many
    String.replace(template, "%d", number(n))
  end

  @doc ~s(Names in a sentence, the last after "and": "Callout and MIT Callout", "A, B, and C".)
  def and_list([one]), do: one
  def and_list([first, second]), do: "#{first} and #{second}"

  def and_list([_, _, _ | _] = items) do
    {rest, [last]} = Enum.split(items, -1)
    Enum.join(rest, ", ") <> ", and " <> last
  end

  @doc ~s(Names in a sentence, the last after "or": "Dana Clark or Eli Haddad", "A, B, or C".)
  def or_list([one]), do: one
  def or_list([first, second]), do: "#{first} or #{second}"

  def or_list([_, _, _ | _] = items) do
    {rest, [last]} = Enum.split(items, -1)
    Enum.join(rest, ", ") <> ", or " <> last
  end

  @doc ~s(A date for letters and sentences: "October 20, 2026". Takes a `Date`, or a time and zone.)
  def date_long(%Date{} = date), do: Calendar.strftime(date, "%B %-d, %Y")
  def date_long(datetime, timezone), do: datetime(datetime, timezone, "%B %-d, %Y")

  @doc ~s(A date for tables and lists: "Oct 20, 2026". Takes a `Date`, or a time and zone.)
  def date_short(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")
  def date_short(datetime, timezone), do: datetime(datetime, timezone, "%x")

  def month_year(datetime, timezone), do: datetime(datetime, timezone, "%b %Y")

  # A time always follows its date after a comma: "Oct 20, 12:00", "Oct 20, 2026, 12:00".

  @doc ~s(A date and time: "Oct 20, 2026, 12:00".)
  def datetime_short(datetime, timezone), do: datetime(datetime, timezone, "%c")

  @doc ~s(The same with the weekday: "Tue Oct 20, 2026, 12:00".)
  def datetime_medium(datetime, timezone), do: datetime(datetime, timezone, "%a %c")

  def time_short(datetime, timezone), do: datetime(datetime, timezone, "%H:%M")

  @doc ~s(A date with no year, in a table under a heading that names the year: "Oct 20".)
  def month_day(datetime, timezone), do: datetime(datetime, timezone, "%b %-d")

  @doc ~s(A date and time with no year: "Oct 20, 12:00".)
  def month_day_time(datetime, timezone), do: datetime(datetime, timezone, "%b %-d, %H:%M")

  def month_day_time_seconds(datetime, timezone),
    do: datetime(datetime, timezone, "%b %-d, %H:%M:%S")

  @doc "A date in a table, with the year only when it is not this year: \"Mar 1\"."
  def day_in_year(%Date{} = date, %Date{} = today),
    do: Calendar.strftime(date, if(date.year == today.year, do: "%b %-d", else: "%b %-d, %Y"))

  @doc "A month's short name, for chart labels: \"Sep\"."
  def month_short(%Date{} = date), do: Calendar.strftime(date, "%b")

  @doc ~s(A month in full with its year, for a chart's tip, "Member since", or a chore activity's title: "September 2025".)
  def month_year_long(%Date{} = date), do: Calendar.strftime(date, "%B %Y")
  def month_year_long(datetime, timezone), do: datetime(datetime, timezone, "%B %Y")

  @doc "A whole number with thousands separators: \"1,204\"."
  def number(n) when is_float(n), do: number(round(n))

  def number(n) when is_integer(n) and n < 0, do: "-" <> number(-n)

  def number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @doc """
  Minutes as whole hours with no unit, for a stat or column whose label says hours, such
  as "Hours in 2026": "1,204".
  """
  def hours(minutes), do: number(div(round(minutes), 60))

  @doc ~s(A count of days: "1 day", "30 days", "1,095 days". Work days out with `Service.Convert`.)
  def days(n) when is_integer(n), do: count(n, one: "1 day", many: "%d days")

  @doc ~s(A length in months, as whole years when it is some: "6 months", "1 year", "3 years", "18 months".)
  def months(n) when is_integer(n) and n > 0 and rem(n, 12) == 0,
    do: count(div(n, 12), one: "1 year", many: "%d years")

  def months(n) when is_integer(n), do: count(n, one: "1 month", many: "%d months")

  @doc ~s(A file's size: "820 bytes", "64 KB", "2.4 MB".)
  def file_size(bytes) when is_integer(bytes) and bytes < 1000,
    do: count(bytes, one: "1 byte", many: "%d bytes")

  def file_size(bytes) when is_integer(bytes) and bytes < 1_000_000,
    do: number(round(bytes / 1000)) <> " KB"

  def file_size(bytes) when is_integer(bytes) do
    tenths = round(bytes / 100_000)

    if rem(tenths, 10) == 0,
      do: number(div(tenths, 10)) <> " MB",
      else: decimals(tenths / 10, 1) <> " MB"
  end

  @doc ~s(A distance in whole km: "42 km", "1,204 km".)
  def km(n) when is_number(n), do: number(n) <> " km"

  @doc ~s(A number to one decimal place, for a column whose header names the unit: "1.5", "2.0".)
  def tenths(n) when is_number(n), do: decimals(n, 1)

  @doc ~s(How long a job took, for admins: "850 ms", "4.2 s", then "3.5 min" from 2 minutes.)
  def run_time(ms) when ms < 1000, do: "#{round(ms)} ms"
  def run_time(ms) when ms < 120_000, do: "#{tenths(ms / 1000)} s"
  def run_time(ms), do: "#{tenths(ms / 60_000)} min"

  @doc """
  Latitude and longitude to `precision` decimal places: "49.75533, -123.13110". Anything
  else, such as why Mapbox found no place, as is. Stored coordinates have no space; see
  `App.Model.Coordinate.to_string/2`.
  """
  def coordinate({lat, lng}, precision),
    do: "#{decimals(lat, precision)}, #{decimals(lng, precision)}"

  def coordinate(other, _precision), do: other

  defp decimals(n, places), do: :erlang.float_to_binary(n / 1, decimals: places)

  defp datetime(nil, _timezone, _format), do: nil

  defp datetime(datetime, timezone, format) do
    user_options = [
      preferred_datetime: "%b %-d, %Y, %H:%M",
      preferred_date: "%b %-d, %Y"
    ]

    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime(format, user_options)
  end

  @doc """
  How long before `now` a datetime was, for things that change by the minute: "just
  now", "4 min ago", "3 hours ago", then the date and time in `timezone`.
  """
  def minutes_ago(nil, _now, _timezone), do: nil

  def minutes_ago(datetime, now, timezone) do
    minutes = div(DateTime.diff(now, datetime), 60)

    cond do
      minutes < 1 -> "just now"
      minutes < 60 -> "#{minutes} min ago"
      minutes < 24 * 60 -> count(div(minutes, 60), one: "%d hour ago", many: "%d hours ago")
      true -> datetime_short(datetime, timezone)
    end
  end

  @doc """
  The day of an activity coming up, in `timezone`: "Today", "Tomorrow", then "Sat Oct 11".
  """
  def day_coming_up(datetime, now, timezone) do
    days = datetime |> local_date(timezone) |> Date.diff(local_date(now, timezone))

    case days do
      0 -> "Today"
      1 -> "Tomorrow"
      _days -> datetime(datetime, timezone, "%a %b %-d")
    end
  end

  @doc """
  How soon an activity starts, or how long ago it started: "in 25 min", "in 3 hours",
  "started 40 min ago", "started 2 hours ago".
  """
  def starts_in(datetime, now) do
    minutes = div(DateTime.diff(datetime, now), 60)

    cond do
      minutes >= 60 -> count(div(minutes, 60), one: "in %d hour", many: "in %d hours")
      minutes > 0 -> "in #{minutes} min"
      minutes == 0 -> "starting now"
      minutes > -60 -> "started #{-minutes} min ago"
      true -> count(div(-minutes, 60), one: "started %d hour ago", many: "started %d hours ago")
    end
  end

  @doc """
  How long before `now` a datetime was, counted in calendar days in `timezone`: "Today",
  "Yesterday", "12 days ago", then "4 months ago".
  """
  def days_ago(nil, _now, _timezone), do: nil

  def days_ago(datetime, now, timezone) do
    seen_on = local_date(datetime, timezone)
    days = now |> local_date(timezone) |> Date.diff(seen_on)

    cond do
      days <= 0 -> "Today"
      days == 1 -> "Yesterday"
      days < 45 -> "#{days} days ago"
      true -> "#{months_or_years(datetime, now)} ago"
    end
  end

  defp local_date(datetime, timezone),
    do: datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

  # From 45 days back: "1 month", "18 months", then whole years.
  defp months_or_years(started_at, finished_at) do
    months = Service.Convert.duration_to_months(started_at, finished_at)

    if months <= 18,
      do: count(months, one: "1 month", many: "%d months"),
      else: "#{round(months / 12)} years"
  end

  @doc """
  A duration as people read it everywhere: "212h 30m", "1,204 hours", "1 hour", "45 min".
  Whole hours are spelled out; under an hour is minutes alone.
  """
  def duration(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours == 1 and mins == 0 -> "1 hour"
      mins == 0 -> "#{number(hours)} hours"
      hours == 0 -> "#{mins} min"
      true -> "#{number(hours)}h #{mins}m"
    end
  end

  def duration(minutes) when is_float(minutes), do: duration(round(minutes))
end

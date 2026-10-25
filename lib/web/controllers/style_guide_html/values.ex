defmodule Web.StyleGuideHTML.Values do
  @moduledoc """
  Every value formatter run on fixed samples, for the style guide's Values page, as
  `[{section, about, [{function, use, [{call, result}]}]}]`. Noon on Oct 20, 2026 in
  Vancouver is "now". A test fails when a Service.Format function is missing here.
  """

  alias App.Model.MemberCard
  alias Service.Format

  @now ~U[2026-10-20 19:00:00Z]
  @zone "America/Vancouver"
  @today ~D[2026-10-20]

  def all, do: [dates(), time_from_now(), quantities(), elsewhere()]

  @doc """
  A section's functions as table rows, one per example: `%{id:, use:, code:, shows:}`, with
  the use on a function's first example only, so each function reads as one block.
  """
  def rows(functions) do
    for {name, use, examples} <- functions,
        {{code, shows}, index} <- Enum.with_index(examples, 1) do
      %{id: "value-#{name}-#{index}", use: if(index == 1, do: use), code: code, shows: shows}
    end
  end

  defp dates do
    {"Dates and times", "In the team's time zone, month first, 24-hour clock.",
     calendar_dates() ++ date_times()}
  end

  defp calendar_dates do
    [
      {:date_long, "Letters and sentences, from a time or a date",
       [
         {"date_long(now, zone)", Format.date_long(@now, @zone)},
         {"date_long(~D[2025-09-28])", Format.date_long(~D[2025-09-28])}
       ]},
      {:date_short, "Tables and lists, from a time or a date",
       [
         {"date_short(now, zone)", Format.date_short(@now, @zone)},
         {"date_short(~D[2025-09-28])", Format.date_short(~D[2025-09-28])}
       ]},
      {:day_in_year, "A table date, with the year only when it is not this year",
       [
         {"day_in_year(~D[2026-03-01], today)", Format.day_in_year(~D[2026-03-01], @today)},
         {"day_in_year(~D[2025-03-01], today)", Format.day_in_year(~D[2025-03-01], @today)}
       ]},
      {:month_day, "A table date under a heading that names the year",
       [{"month_day(now, zone)", Format.month_day(@now, @zone)}]},
      {:month_year, "Award dates", [{"month_year(now, zone)", Format.month_year(@now, @zone)}]},
      {:month_short, "Chart labels",
       [{"month_short(~D[2025-09-01])", Format.month_short(~D[2025-09-01])}]},
      {:month_year_long, "A chart's tip, Member since, and a chore activity's title",
       [
         {"month_year_long(~D[2025-09-01])", Format.month_year_long(~D[2025-09-01])},
         {"month_year_long(now, zone)", Format.month_year_long(@now, @zone)}
       ]}
    ]
  end

  defp date_times do
    [
      {:datetime_short, "A date and time",
       [{"datetime_short(now, zone)", Format.datetime_short(@now, @zone)}]},
      {:datetime_medium, "The same with the weekday",
       [{"datetime_medium(now, zone)", Format.datetime_medium(@now, @zone)}]},
      {:time_short, "A time alone", [{"time_short(now, zone)", Format.time_short(@now, @zone)}]},
      {:month_day_time, "A time this year",
       [{"month_day_time(now, zone)", Format.month_day_time(@now, @zone)}]},
      {:month_day_time_seconds, "The same to the second",
       [{"month_day_time_seconds(now, zone)", Format.month_day_time_seconds(@now, @zone)}]}
    ]
  end

  defp time_from_now do
    {"Time from now", "How long ago or how soon, counted from now.", ago() ++ coming_up()}
  end

  defp ago do
    [
      {:minutes_ago, "Things that change by the minute",
       [
         {"minutes_ago(now - 4 min, now, zone)",
          Format.minutes_ago(~U[2026-10-20 18:56:00Z], @now, @zone)},
         {"minutes_ago(now - 3 h, now, zone)",
          Format.minutes_ago(~U[2026-10-20 16:00:00Z], @now, @zone)},
         {"minutes_ago(now - 2 days, now, zone)",
          Format.minutes_ago(~U[2026-10-18 19:00:00Z], @now, @zone)}
       ]},
      {:days_ago, "Last seen, in calendar days",
       [
         {"days_ago(now - 1 day, now, zone)",
          Format.days_ago(~U[2026-10-19 19:00:00Z], @now, @zone)},
         {"days_ago(now - 12 days, now, zone)",
          Format.days_ago(~U[2026-10-08 19:00:00Z], @now, @zone)},
         {"days_ago(now - 120 days, now, zone)",
          Format.days_ago(~U[2026-06-22 19:00:00Z], @now, @zone)},
         {"days_ago(now - 5 years, now, zone)",
          Format.days_ago(~U[2021-10-20 19:00:00Z], @now, @zone)}
       ]}
    ]
  end

  defp coming_up do
    [
      {:day_coming_up, "The day of an activity coming up",
       [
         {"day_coming_up(now + 1 day, now, zone)",
          Format.day_coming_up(~U[2026-10-21 19:00:00Z], @now, @zone)},
         {"day_coming_up(now + 5 days, now, zone)",
          Format.day_coming_up(~U[2026-10-25 19:00:00Z], @now, @zone)}
       ]},
      {:starts_in, "How soon an activity starts",
       [
         {"starts_in(now + 25 min, now)", Format.starts_in(~U[2026-10-20 19:25:00Z], @now)},
         {"starts_in(now - 2 h, now)", Format.starts_in(~U[2026-10-20 17:00:00Z], @now)}
       ]}
    ]
  end

  defp quantities do
    member = [one: "1 member", many: "%d members"]

    {"Numbers and quantities",
     "A number and its unit always come from one of these, never written by hand.",
     [
       {:number, "A whole number",
        [{"number(1204)", Format.number(1204)}, {"number(12.6)", Format.number(12.6)}]},
       {:count, "A count with its noun",
        [
          {~s{count(1, one: "1 member", many: "%d members")}, Format.count(1, member)},
          {~s{count(1204, one: "1 member", many: "%d members")}, Format.count(1204, member)}
        ]}
     ] ++
       name_lists() ++
       [
         {:duration, "Hours and minutes, everywhere",
          [
            {"duration(12_750)", Format.duration(12_750)},
            {"duration(12_120)", Format.duration(12_120)},
            {"duration(60)", Format.duration(60)},
            {"duration(45)", Format.duration(45)}
          ]},
         {:hours, "Minutes as whole hours, under a label that says hours",
          [{"hours(72_299)", Format.hours(72_299)}]},
         {:tenths, "One decimal place, under a label that names the unit",
          [{"tenths(1.5)", Format.tenths(1.5)}]},
         {:days, "A count of days", [{"days(1)", Format.days(1)}, {"days(30)", Format.days(30)}]},
         {:months, "How long a qualification lasts",
          [{"months(6)", Format.months(6)}, {"months(36)", Format.months(36)}]},
         {:file_size, "A file's size",
          [
            {"file_size(64_200)", Format.file_size(64_200)},
            {"file_size(2_400_000)", Format.file_size(2_400_000)}
          ]},
         {:km, "A distance", [{"km(42)", Format.km(42)}]},
         {:coordinate, "A place",
          [
            {"coordinate({49.75533, -123.1311}, 5)", Format.coordinate({49.75533, -123.1311}, 5)},
            {"coordinate({49.75533, -123.1311}, 3)", Format.coordinate({49.75533, -123.1311}, 3)}
          ]},
         {:run_time, "How long a job took, for admins",
          [
            {"run_time(850)", Format.run_time(850)},
            {"run_time(4_200)", Format.run_time(4_200)},
            {"run_time(210_000)", Format.run_time(210_000)}
          ]}
       ]}
  end

  # Split from quantities only to keep each function short.
  defp name_lists do
    [
      {:and_list, "Names in a sentence, such as what deleting a group stops",
       [
         {~s{and_list(["Callout", "MIT Callout"])}, Format.and_list(["Callout", "MIT Callout"])},
         {~s{and_list(["A", "B", "C"])}, Format.and_list(["A", "B", "C"])}
       ]},
      {:or_list, "Names in a sentence, such as who a reminder skips",
       [
         {~s{or_list(["Dana Clark", "Eli Haddad"])},
          Format.or_list(["Dana Clark", "Eli Haddad"])},
         {~s{or_list(["A", "B", "C"])}, Format.or_list(["A", "B", "C"])}
       ]}
    ]
  end

  defp elsewhere do
    {"Elsewhere", "Formatters that belong to one kind of value, beside its code.",
     [
       {:"Service.Phone.format", "A phone number, from a refresh or as typed",
        [
          {~s{Service.Phone.format("(604) 555 1234")}, Service.Phone.format("(604) 555 1234")},
          {~s{Service.Phone.format("+44 20 7946 0958")}, Service.Phone.format("+44 20 7946 0958")}
        ]},
       {:"MemberCard.format_code", "An ID card's code",
        [{~s{MemberCard.format_code("K7Q4M2XA")}, MemberCard.format_code("K7Q4M2XA")}]}
     ]}
  end
end

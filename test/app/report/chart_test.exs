defmodule App.Report.ChartTest do
  # A report's chart (#826): the axis, zero-filled buckets, series, a stat's own total,
  # and compare year, from the rows the report shows.
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Report
  alias App.Report.BuiltIn
  alias App.Report.Error

  @now ~U[2026-06-15 19:00:00Z]

  defp chart(team, text, params \\ %{}) do
    {:ok, view} = Report.page(text, team, params, @now)
    view.chart
  end

  defp error(team, text) do
    {:error, error} = Report.check(text, team)
    Error.text(error)
  end

  test "columns fill every month the where allows, with each kind its own series" do
    team = team_fixture()
    activity_fixture(team, %{activity_kind: "incident", started_at: ~U[2026-03-10 18:00:00Z]})
    activity_fixture(team, %{activity_kind: "exercise", started_at: ~U[2026-03-12 18:00:00Z]})
    activity_fixture(team, %{activity_kind: "incident", started_at: ~U[2025-08-01 18:00:00Z]})

    chart = chart(team, BuiltIn.get("activities-by-month").query)

    assert chart.kind == :columns
    assert length(chart.data.columns) == 12
    assert hd(chart.data.columns).label == "Jul"
    march = Enum.find(chart.data.columns, &(&1.label == "Mar"))
    assert march.values == %{incident: 1, exercise: 1}
    assert Enum.find(chart.data.columns, &(&1.label == "Aug")).values.incident == 1
    assert Enum.find(chart.data.columns, &(&1.label == "Apr")).values.incident == 0

    chart = chart(team, BuiltIn.get("activities-by-month").query, %{"when" => "2025"})
    assert length(chart.data.columns) == 12
    assert hd(chart.data.columns).label == "Jan"
  end

  test "a stat's number is the query's own total, against the same days last year" do
    team = team_fixture()
    member = member_fixture(team)
    this = activity_fixture(team, %{started_at: ~U[2026-02-01 18:00:00Z]})
    later = activity_fixture(team, %{started_at: ~U[2026-03-01 18:00:00Z]})
    last = activity_fixture(team, %{started_at: ~U[2025-02-01 18:00:00Z]})
    # After this day last year, so not part of "this time last year".
    activity_fixture(team, %{started_at: ~U[2025-09-01 18:00:00Z]})
    for a <- [this, later, last], do: attendance_fixture(a, member, %{duration_in_minutes: 120})

    chart = chart(team, BuiltIn.get("activities-this-year").query)
    assert chart.data.value == 2
    assert chart.before.value == 1
    assert chart.data.spark == [0, 1, 1, 0, 0, 0]

    chart = chart(team, BuiltIn.get("member-hours-this-year").query)
    assert chart.hours?
    assert chart.data.value == 240
    assert chart.before.value == 120
  end

  # Adding up months would count an activity with rows in two months twice.
  test "a stat counts distinct across its axis once" do
    team = team_fixture()
    activity = activity_fixture(team, %{started_at: ~U[2026-01-31 18:00:00Z]})
    member = member_fixture(team)
    attendance_fixture(activity, member, %{started_at: ~U[2026-01-31 18:00:00Z]})
    attendance_fixture(activity, member_fixture(team), %{started_at: ~U[2026-02-01 18:00:00Z]})

    chart =
      chart(team, """
      select month(started_at), count(distinct activity)
      from attendance
      where started_at = THIS_YEAR
      group by month(started_at)
      chart stat
      """)

    assert chart.data.value == 1
  end

  test "a stat with no axis takes its second number as a note" do
    team = team_fixture()
    member_fixture(team, %{joined_at: ~U[2026-02-01 12:00:00Z]})
    member_fixture(team, %{joined_at: ~U[2020-02-01 12:00:00Z]})

    chart = chart(team, BuiltIn.get("current-members").query)
    assert chart.data.value == 2
    assert {1, %{label: "Joined this year"}} = chart.data.note
  end

  test "a calendar and a week fill their grids" do
    team = team_fixture()
    activity_fixture(team, %{activity_kind: "incident", started_at: ~U[2026-06-13 02:00:00Z]})

    chart = chart(team, BuiltIn.get("every-day-out").query)
    assert length(chart.data.days) == 365
    assert {~D[2026-06-12], 1} in chart.data.days

    chart = chart(team, BuiltIn.get("when-incidents-start").query)
    assert length(chart.data.rows) == 7
    # Friday at 19:00 in Vancouver.
    assert chart.data.rows |> Enum.at(4) |> Enum.at(19) == 1
  end

  test "cumulative adds up as it goes" do
    team = team_fixture()
    activity_fixture(team, %{started_at: ~U[2026-01-10 18:00:00Z]})
    activity_fixture(team, %{started_at: ~U[2026-03-10 18:00:00Z]})

    chart =
      chart(team, """
      select month(started_at), count(id)
      from activities
      where started_at = THIS_YEAR and started_at <= NOW
      group by month(started_at)
      chart lines cumulative
      """)

    assert [%{values: [1, 1, 2, 2, 2, 2]}] = chart.data.series
  end

  test "a chart says what its rows must hold" do
    team = team_fixture()

    assert error(team, "select title from activities\nchart columns") ==
             "Line 2: chart columns draws numbers. Select a count, a sum, or a number field."

    assert error(
             team,
             "select month(started_at), count(id) from activities group by month(started_at)\nchart calendar"
           ) =~
             "A calendar takes date(started_at) first"

    assert error(team, "select title, attended_count from activities\nchart bars compare year") =~
             "compare year works with chart stat or chart lines."

    assert error(team, "select title from activities\nchart pie") =~
             "Write one of stat, columns, lines, bars, calendar, week after chart."
  end

  test "a chart draws at most its limit, and says how to narrow it" do
    team = team_fixture()

    {:error, error} =
      Report.page(
        "select date(started_at), count(id) from activities where started_at = LAST_N_DAYS:900 group by date(started_at)\nchart calendar",
        team,
        %{},
        @now
      )

    assert Error.text(error) =~ "chart calendar draws at most 366"
  end
end

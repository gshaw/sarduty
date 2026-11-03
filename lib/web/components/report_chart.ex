defmodule Web.Components.ReportChart do
  @moduledoc """
  A report's chart (#826), between its filters and its rows. App.Report.Chart shapes the
  rows; this draws them with the app's own charts (Web.Components.Chart), so a chart
  report looks like the Dashboard's. Every chart keeps its hidden table, and the report's
  own table under it lists the same rows.
  """
  use Web, :function_component

  import Web.Components.ActivityMap
  import Web.Components.Chart

  alias App.Report.Chart
  alias App.ViewData.TeamDashboardCharts
  alias Service.Format
  alias Web.Components.ActivityMap
  alias Web.Components.ReportTable

  @max_bars 15

  attr :id, :string, required: true
  attr :chart, :map, required: true, doc: "App.Report.Chart.build/4's chart"
  attr :records, :map, required: true, doc: "from App.ViewData.ReportRecords.load/3"
  attr :team, :any, required: true
  attr :href, :string, default: nil, doc: "where a stat's label goes, such as its report"
  attr :now, :any, default: nil, doc: "for a map's large dots, the last 30 days"

  def report_chart(%{chart: %{kind: :stat}} = assigns) do
    ~H"""
    <div id={@id} class="chart-stats report-chart">
      <.report_stat id={"#{@id}-stat"} chart={@chart} href={@href} />
    </div>
    """
  end

  def report_chart(%{chart: %{kind: :columns}} = assigns) do
    ~H"""
    <section id={@id} class="card report-chart">
      <.column_chart id={"#{@id}-columns"} columns={@chart.data.columns} series={@chart.data.series} />
    </section>
    """
  end

  def report_chart(%{chart: %{kind: :lines}} = assigns) do
    assigns = assign(assigns, series: line_series(assigns.chart))

    ~H"""
    <section id={@id} class="card report-chart">
      <.line_chart id={"#{@id}-lines"} labels={@chart.data.labels} series={@series} />
    </section>
    """
  end

  def report_chart(%{chart: %{kind: :bars}} = assigns) do
    rows =
      assigns.chart.data.rows
      |> Enum.take(@max_bars)
      |> Enum.map(&bar(&1, assigns.records, assigns.team))

    assigns =
      assign(assigns,
        rows: rows,
        max: @max_bars,
        more?: length(assigns.chart.data.rows) > @max_bars
      )

    ~H"""
    <section id={@id} class="card report-chart">
      <.bar_list id={"#{@id}-bars"} rows={@rows} />
      <p :if={@more?} class="hint mt-2">The first {@max} rows. The table has them all.</p>
    </section>
    """
  end

  # The Dashboard's map, from the report's places, by its rules: nothing over 150 km from
  # the team's base, and large dots for the last 30 days.
  def report_chart(%{chart: %{kind: :map}} = assigns) do
    assigns =
      assign(assigns,
        map: map(assigns.chart, assigns.records, assigns.team, assigns.now, {960, 480}),
        max: Chart.limits().map
      )

    ~H"""
    <section id={@id} class="card report-chart">
      <p class="chart-caption">Large dots are the last 30 days.</p>
      <.activity_map
        :if={@map}
        id={"#{@id}-map"}
        map={@map}
        label="Map of the report's places"
        overlay={false}
      />
      <p :if={!@map} class="chart-caption">No activity with a place.</p>
      <p :if={@chart.data.more > 0} class="hint mt-2">
        The first {Format.number(@max)} places. Narrow the where for the rest.
      </p>
    </section>
    """
  end

  def report_chart(%{chart: %{kind: :calendar}} = assigns) do
    ~H"""
    <section id={@id} class="card report-chart">
      <.calendar id={"#{@id}-calendar"} days={@chart.data.days} />
    </section>
    """
  end

  def report_chart(%{chart: %{kind: :week}} = assigns) do
    ~H"""
    <section id={@id} class="card report-chart">
      <.week_grid id={"#{@id}-week"} rows={@chart.data.rows} />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :chart, :map, required: true, doc: "a `chart stat`'s chart"
  attr :label, :string, default: nil, doc: "in place of its column's label"
  attr :href, :string, default: nil
  attr :series, :atom, default: :primary

  @doc "A `chart stat` as one stat, for a row of them such as the Dashboard's."
  def report_stat(assigns) do
    assigns = assign(assigns, data: assigns.chart.data, delta: delta(assigns.chart))

    ~H"""
    <.stat
      id={@id}
      value={number_text(@data.value, @chart)}
      label={@label || @chart.label || ""}
      href={@href}
      delta={@delta}
      series={@series}
    >
      <.sparkline :if={@data.spark} values={spark(@data.spark, @chart)} series={@series} />
    </.stat>
    """
  end

  @doc """
  A `chart map`'s map at `size`, from its places and the rows' activities, or nil when
  none is near the team's base.
  """
  def map(chart, records, team, now, size) do
    chart.data.places
    |> map_points(records, team, now)
    |> ActivityMap.build(size, padding: 24)
  end

  # With compare year, this year's line beside last year's in grey. Hours in whole hours,
  # so the ticks land on round numbers.
  defp line_series(%{data: data, before: before} = chart) do
    series =
      case before do
        nil ->
          data.series

        before ->
          [first | _] = data.series

          [
            %{first | label: "This year"},
            %{hd(before.series) | key: :compare, label: "Last year"}
          ]
      end

    Enum.map(series, fn s -> %{key: s.key, label: s.label, values: spark(s.values, chart)} end)
  end

  defp spark(values, %{hours?: true}), do: Enum.map(values, &(&1 && div(&1, 60)))
  defp spark(values, _chart), do: values

  defp number_text(minutes, %{hours?: true}), do: Format.hours(minutes)
  defp number_text(n, _chart), do: Format.number(n)

  # As the Dashboard words it: "12 more than this time last year", or a stat's second
  # number, "1 joined this year".
  defp delta(%{before: nil, data: %{note: {n, column}}}),
    do: "#{Format.number(n)} #{String.downcase(column.label || "")}"

  defp delta(%{before: nil}), do: nil

  defp delta(%{data: %{value: now}, before: %{value: before}} = chart) do
    {now, before} = if chart.hours?, do: {div(now, 60), div(before, 60)}, else: {now, before}

    cond do
      now > before -> "#{Format.number(now - before)} more than this time last year"
      now < before -> "#{Format.number(before - now)} fewer than this time last year"
      true -> "Same as this time last year"
    end
  end

  defp bar(%{label: id, label_column: %{type: {:record, kind}}} = row, records, team) do
    record = records |> Map.get(kind, %{}) |> Map.get(id)

    %{
      label: record_name(record),
      value: row.value,
      text: row.text,
      href: record_path(kind, id, team)
    }
  end

  defp bar(row, _records, team) do
    label =
      if row.label == nil,
        do: "None",
        else: ReportTable.value_text(row.label, row.label_column, team)

    %{label: label, value: row.value, text: row.text, href: nil}
  end

  defp map_points(places, records, team, now) do
    activities = Map.get(records, :activity, %{})

    places
    |> Enum.flat_map(fn {id, place} ->
      case activities[id] do
        nil -> []
        activity -> [map_activity(activity, place)]
      end
    end)
    |> TeamDashboardCharts.map_points(team, now || DateTime.utc_now())
  end

  defp map_activity(activity, place) do
    %{
      title: activity.title,
      started_at: activity.started_at,
      coordinate: place,
      kind: TeamDashboardCharts.kind(activity.activity_kind)
    }
  end

  defp record_name(%{name: name}), do: name
  defp record_name(%{title: title}), do: title
  defp record_name(_record), do: ""

  defp record_path(:member, id, team), do: ~p"/teams/#{team}/members/#{id}"
  defp record_path(:activity, id, team), do: ~p"/teams/#{team}/activities/#{id}"
  defp record_path(:qualification, id, team), do: ~p"/teams/#{team}/qualifications/#{id}"
  defp record_path(:group, id, team), do: ~p"/teams/#{team}/groups/#{id}"
  defp record_path(_kind, _id, _team), do: nil
end

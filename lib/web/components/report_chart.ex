defmodule Web.Components.ReportChart do
  @moduledoc """
  Experiment (charts): a report's chart, above its rows. App.Report.Chart shapes the
  rows; this draws them with the app's own charts (Web.Components.Chart), so a chart
  report looks like the Dashboard's. Every chart still carries its hidden table, and the
  report's own table under it shows the same rows.
  """
  use Web, :function_component

  import Web.Components.Chart

  alias App.Report.Chart
  alias Service.Format

  attr :id, :string, required: true
  attr :chart, Chart, required: true
  attr :run, :map, required: true, doc: "App.Report.Chart.run/4's result"
  attr :records, :map, required: true, doc: "from App.ViewData.ReportRecords.load/3"
  attr :team, :any, required: true
  attr :label, :string, default: nil, doc: "a stat's label, when not its column's"

  def report_chart(%{chart: %{kind: :stat}} = assigns) do
    assigns = assign(assigns, data: assigns.run.data, delta: delta(assigns.run))

    ~H"""
    <div id={@id} class="chart-stats report-chart">
      <.stat
        id={"#{@id}-stat"}
        value={stat_text(@data.value, @run.result)}
        label={@label || stat_label(@run.result)}
        delta={@delta}
      >
        <.sparkline :if={@data.spark} values={@data.spark} />
      </.stat>
    </div>
    """
  end

  def report_chart(%{chart: %{kind: :columns}} = assigns) do
    ~H"""
    <section id={@id} class="card report-chart">
      <.column_chart
        id={"#{@id}-columns"}
        columns={@run.data.columns}
        series={@run.data.series}
        caption={@chart.name}
      />
    </section>
    """
  end

  def report_chart(%{chart: %{kind: :lines}} = assigns) do
    assigns = assign(assigns, series: line_series(assigns.run), format: &Format.number/1)

    ~H"""
    <section id={@id} class="card report-chart">
      <.line_chart id={"#{@id}-lines"} labels={@run.data.labels} series={@series} format={@format} />
    </section>
    """
  end

  def report_chart(%{chart: %{kind: :bars}} = assigns) do
    rows =
      assigns.run.data.rows |> Enum.take(15) |> Enum.map(&bar(&1, assigns.records, assigns.team))

    assigns = assign(assigns, rows: rows)

    ~H"""
    <section id={@id} class="card report-chart">
      <.bar_list id={"#{@id}-bars"} rows={@rows} />
    </section>
    """
  end

  def report_chart(%{chart: %{kind: :calendar}} = assigns) do
    ~H"""
    <section id={@id} class="card report-chart">
      <.calendar id={"#{@id}-calendar"} days={@run.data.days} />
    </section>
    """
  end

  def report_chart(%{chart: %{kind: :week}} = assigns) do
    ~H"""
    <section id={@id} class="card report-chart">
      <.week_grid id={"#{@id}-week"} rows={@run.data.rows} />
    </section>
    """
  end

  # With compare year, this year's line beside last year's in grey. Hours in whole hours,
  # so the ticks land on round numbers.
  defp line_series(run) do
    series =
      case run.before_data do
        nil ->
          run.data.series

        before ->
          [first | _] = run.data.series

          [
            %{first | label: "This year"},
            %{hd(before.series) | key: :compare, label: "Last year"}
          ]
      end

    if hours?(run.result),
      do: Enum.map(series, fn s -> %{s | values: Enum.map(s.values, &(&1 && div(&1, 60)))} end),
      else: series
  end

  defp stat_text(minutes, result),
    do: if(hours?(result), do: Format.hours(minutes), else: Format.number(minutes))

  defp stat_label(%{columns: columns}) do
    columns |> Enum.find(&(&1.type in [:number, :hours, :km])) |> Map.get(:label)
  end

  defp hours?(%{columns: columns}), do: Enum.any?(columns, &(&1.type == :hours))

  # As the Dashboard words it: "12 more than this time last year", or a second number,
  # "1 joined this year".
  defp delta(%{before_data: nil, data: %{note: {n, column}}}),
    do: "#{Format.number(n)} #{String.downcase(column.label)}"

  defp delta(%{before_data: nil}), do: nil

  defp delta(%{data: %{value: now}, before_data: %{value: before}, result: result}) do
    {now, before} = if hours?(result), do: {div(now, 60), div(before, 60)}, else: {now, before}

    cond do
      now > before -> "#{Format.number(now - before)} more than this time last year"
      now < before -> "#{Format.number(before - now)} fewer than this time last year"
      true -> "Same as this time last year"
    end
  end

  defp bar(%{label: id, label_type: {:record, kind}} = row, records, team) do
    record = records |> Map.get(kind, %{}) |> Map.get(id)
    Map.merge(row, %{label: record_name(record), href: record_path(kind, id, team)})
  end

  defp bar(row, _records, _team), do: Map.merge(row, %{label: to_string(row.label), href: nil})

  defp record_name(%{name: name}), do: name
  defp record_name(%{title: title}), do: title
  defp record_name(_record), do: ""

  defp record_path(:member, id, team), do: ~p"/teams/#{team}/members/#{id}"
  defp record_path(:qualification, id, team), do: ~p"/teams/#{team}/qualifications/#{id}"
  defp record_path(_kind, _id, _team), do: nil
end

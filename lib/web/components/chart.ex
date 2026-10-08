defmodule Web.Components.Chart do
  @moduledoc """
  Charts drawn on the server, in HTML and SVG, with no JavaScript. Styles are in
  assets/css/components/chart.css and the guide's samples at /styles/chart.

  A series is `{key, label}`. The key picks the colour (`series-incident`,
  `series-exercise`, `series-event`, `series-primary`, `series-compare`), so an entity keeps
  its colour whatever else is on the chart. Every chart carries a hidden table of its
  numbers, and hover tooltips only repeat what the table says.
  """
  use Phoenix.Component

  @doc "The keys beside a chart with two or more series."
  attr :series, :list, required: true
  attr :mark, :atom, default: :box, values: [:box, :line, :dot]

  def legend(assigns) do
    ~H"""
    <ul class="chart-legend">
      <li :for={{key, label} <- @series}>
        <i class={[
          "chart-key",
          "series-#{key}",
          @mark == :line && "is-line",
          @mark == :dot && "is-dot"
        ]}></i>
        {label}
      </li>
    </ul>
    """
  end

  @doc """
  Columns over time, stacked by series from the baseline. Each column is
  `%{label: "Sep", values: %{incident: 3}, tip: "Sep 2025\\n3 incidents"}`.
  """
  attr :id, :string, required: true
  attr :columns, :list, required: true
  attr :series, :list, required: true
  attr :height, :integer, default: 200
  attr :caption, :string, default: nil

  def column_chart(assigns) do
    totals = Enum.map(assigns.columns, fn col -> col.values |> Map.values() |> Enum.sum() end)
    {top, ticks} = nice_ticks(Enum.max(totals, fn -> 0 end))
    assigns = assign(assigns, top: top, ticks: ticks)

    ~H"""
    <figure id={@id} class="chart" style="margin: 0">
      <.legend :if={length(@series) > 1} series={@series} />
      <div class="chart-plot" style={"--plot-h: #{@height}px"}>
        <.ticks ticks={@ticks} top={@top} />
        <div class="chart-columns">
          <div :for={col <- @columns} class="chart-column" data-tip={col[:tip]}>
            <i
              :for={{key, _label} <- @series}
              :if={Map.get(col.values, key, 0) > 0}
              class={"series-#{key}"}
              style={"height: max(calc(#{percent(Map.get(col.values, key), @top)}% - 2px), 2px)"}
            ></i>
          </div>
        </div>
      </div>
      <div class="chart-labels"><span :for={col <- @columns}>{col.label}</span></div>
      <table class="chart-table">
        <caption :if={@caption}>{@caption}</caption>
        <tr>
          <th></th>
          <th :for={{_key, label} <- @series}>{label}</th>
        </tr>
        <tr :for={col <- @columns}>
          <th>{col.label}</th>
          <td :for={{key, _label} <- @series}>{Map.get(col.values, key, 0)}</td>
        </tr>
      </table>
    </figure>
    """
  end

  @doc """
  Lines over the same labels, such as this year and last year by month. Each series is
  `%{key: :primary, label: "2025", values: [12, 40, nil]}`; a nil ends the line there. The
  first series gets a wash under it and its value at the end.
  """
  attr :id, :string, required: true
  attr :labels, :list, required: true
  attr :series, :list, required: true
  attr :height, :integer, default: 200
  attr :format, :any, default: &Integer.to_string/1
  attr :caption, :string, default: nil

  def line_chart(assigns) do
    max =
      assigns.series
      |> Enum.flat_map(& &1.values)
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> 0 end)

    {top, ticks} = nice_ticks(max)
    n = length(assigns.labels)
    lines = Enum.map(assigns.series, &Map.put(&1, :points, line_points(&1.values, n, top)))
    tips = line_tips(assigns.labels, assigns.series, assigns.format)

    assigns = assign(assigns, top: top, ticks: ticks, lines: lines, tips: tips)

    ~H"""
    <figure id={@id} class="chart" style="margin: 0">
      <.legend series={Enum.map(@series, &{&1.key, &1.label})} mark={:line} />
      <div class="chart-plot" style={"--plot-h: #{@height}px"}>
        <.ticks ticks={@ticks} top={@top} format={@format} />
        <svg class="chart-line" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
          <%= for {line, index} <- @lines |> Enum.reverse() |> Enum.with_index() do %>
            <polygon
              :if={index == length(@lines) - 1 and length(line.points) > 1}
              class={"series-#{line.key}"}
              points={area_points(line.points)}
            />
            <polyline class={"series-#{line.key}"} points={svg_points(line.points)} />
          <% end %>
        </svg>
        <%= for {line, index} <- Enum.with_index(@lines), {x, y} <- Enum.take(line.points, -1) do %>
          <span class={["chart-dot", "series-#{line.key}"]} style={"left: #{x}%; top: #{y}%"}></span>
          <span :if={index == 0} class="chart-end-label" style={"left: #{x}%; top: #{y}%"}>
            {@format.(line.values |> Enum.reject(&is_nil/1) |> List.last())}
          </span>
        <% end %>
        <div class="chart-hover">
          <span :for={tip <- @tips} data-tip={tip}></span>
        </div>
      </div>
      <div class="chart-labels"><span :for={label <- @labels}>{label}</span></div>
      <table class="chart-table">
        <caption :if={@caption}>{@caption}</caption>
        <tr>
          <th></th>
          <th :for={s <- @series}>{s.label}</th>
        </tr>
        <tr :for={{label, i} <- Enum.with_index(@labels)}>
          <th>{label}</th>
          <td :for={s <- @series}>{s.values |> Enum.at(i) |> then(&(&1 && @format.(&1)))}</td>
        </tr>
      </table>
    </figure>
    """
  end

  # Each value's place in the plot, in percent, centred in its label's slot. Nils drop out.
  defp line_points(values, n, top) do
    values
    |> Enum.with_index()
    |> Enum.reject(fn {v, _i} -> is_nil(v) end)
    |> Enum.map(fn {v, i} -> {(i + 0.5) / n * 100, 100 - percent(v, top)} end)
  end

  # One tooltip per label: the label, then each series' value there.
  defp line_tips(labels, series, format) do
    labels
    |> Enum.with_index()
    |> Enum.map(fn {label, i} ->
      rows = for s <- series, v = Enum.at(s.values, i), v != nil, do: "#{s.label}: #{format.(v)}"
      Enum.join([label | rows], "\n")
    end)
  end

  @doc "A trend with no axes, for a stat. The last value gets a dot."
  attr :values, :list, required: true
  attr :series, :atom, default: :primary

  def sparkline(assigns) do
    values = assigns.values
    max = Enum.max(values, fn -> 0 end)
    n = max(length(values) - 1, 1)

    points =
      values
      |> Enum.with_index()
      |> Enum.map(fn {v, i} -> {i / n * 100, 96 - percent(v, max(max, 1)) * 0.92} end)

    assigns = assign(assigns, points: points)

    ~H"""
    <div class={["sparkline", "series-#{@series}"]} aria-hidden="true">
      <svg class="chart-line" viewBox="0 0 100 100" preserveAspectRatio="none">
        <polygon points={area_points(@points)} />
        <polyline points={svg_points(@points)} />
      </svg>
      <span
        :if={@points != []}
        class="chart-dot"
        style={"left: #{@points |> List.last() |> elem(0)}%; top: #{@points |> List.last() |> elem(1)}%"}
      ></span>
    </div>
    """
  end

  @doc "A number, what it counts, and an optional comparison and trend."
  attr :id, :string, default: nil
  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :href, :string, default: nil
  attr :delta, :string, default: nil
  attr :series, :atom, default: :primary
  slot :inner_block

  def stat(assigns) do
    ~H"""
    <div id={@id} class={["chart-stat", "series-#{@series}"]}>
      <span class="value">{@value}</span>
      <.link :if={@href} navigate={@href} class="label">{@label}</.link>
      <span :if={!@href} class="label">{@label}</span>
      <span :if={@delta} class="delta">{@delta}</span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A year of days, a column per week with Monday at the top, shaded by count. `days` is
  `[{date, count}]`, oldest first.
  """
  attr :id, :string, required: true
  attr :days, :list, required: true
  attr :noun, :list, default: [one: "%d activity", many: "%d activities"]

  def calendar(assigns) do
    days = assigns.days
    max = days |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)

    pad = calendar_pad(days)
    weeks = div(pad + length(days) + 6, 7)

    assigns =
      assign(assigns, max: max, pad: pad, months: calendar_months(days, pad, weeks), weeks: weeks)

    ~H"""
    <figure id={@id} class="chart chart-calendar-scroll" style="margin: 0">
      <div class="chart-calendar">
        <div class="chart-calendar-months">
          <span :for={{label, left} <- @months} style={"left: #{left}%"}>{label}</span>
        </div>
        <div class="chart-calendar-days">
          <span :for={day <- ~w(Mon · Wed · Fri · Sun)}>{if day != "·", do: day}</span>
        </div>
        <div class="chart-calendar-grid" style={"grid-template-columns: repeat(#{@weeks}, 1fr)"}>
          <i :for={_ <- List.duplicate(nil, @pad)} class="is-empty"></i>
          <i
            :for={{date, count} <- @days}
            class={"shade-#{Service.TimeBuckets.level(count, @max)}"}
            title={"#{Service.Format.day(date)}: #{Service.Format.count(count, @noun)}"}
          ></i>
        </div>
      </div>
      <.scale />
      <table class="chart-table">
        <tr :for={{date, count} <- @days} :if={count > 0}>
          <th>{Service.Format.day(date)}</th>
          <td>{count}</td>
        </tr>
      </table>
    </figure>
    """
  end

  # Empty cells before the first day, so each column starts on a Monday.
  defp calendar_pad([{first, _count} | _]), do: Date.day_of_week(first) - 1
  defp calendar_pad([]), do: 0

  # Each month's name over the week its first day falls in, as a left offset in percent.
  defp calendar_months(days, pad, weeks) do
    for {{date, _count}, i} <- Enum.with_index(days), date.day == 1 do
      {Service.Format.month_short(date), div(i + pad, 7) / weeks * 100}
    end
  end

  @doc """
  When things happen in the week: a row per day, Monday first, and a count per hour in
  each. `rows` is 7 lists of 24 counts, from `Service.TimeBuckets.week_rows/1`.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :noun, :list, default: [one: "%d incident", many: "%d incidents"]

  def week_grid(assigns) do
    max = assigns.rows |> List.flatten() |> Enum.max(fn -> 0 end)
    days = Enum.zip(~w(Mon Tue Wed Thu Fri Sat Sun), assigns.rows)
    assigns = assign(assigns, max: max, days: days)

    ~H"""
    <figure id={@id} class="chart" style="margin: 0">
      <div class="chart-week">
        <%= for {day, counts} <- @days do %>
          <span>{day}</span>
          <i
            :for={{count, hour} <- Enum.with_index(counts)}
            class={"shade-#{Service.TimeBuckets.level(count, @max)}"}
            title={"#{day} #{pad_hour(hour)}:00: #{Service.Format.count(count, @noun)}"}
          ></i>
        <% end %>
        <span></span>
        <span :for={hour <- [0, 6, 12, 18]} class="hour">{pad_hour(hour)}:00</span>
      </div>
      <.scale />
      <table class="chart-table">
        <tr>
          <th></th>
          <th :for={hour <- 0..23}>{pad_hour(hour)}:00</th>
        </tr>
        <tr :for={{day, counts} <- @days}>
          <th>{day}</th>
          <td :for={count <- counts}>{count}</td>
        </tr>
      </table>
    </figure>
    """
  end

  @doc """
  A ranked list with a bar per row, longest first. Each row is
  `%{label: "Avery Chen", value: 212, text: "212h", href: "/…"}`.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :series, :atom, default: :primary

  def bar_list(assigns) do
    max = assigns.rows |> Enum.map(& &1.value) |> Enum.max(fn -> 0 end)
    assigns = assign(assigns, max: max)

    ~H"""
    <ul id={@id} class={["chart-bars", "series-#{@series}"]}>
      <li :for={row <- @rows}>
        <span class="name">
          <.link :if={row[:href]} navigate={row.href}>{row.label}</.link>
          <span :if={!row[:href]}>{row.label}</span>
        </span>
        <span class="track">
          <i style={"width: #{percent(row.value, max(@max, 1)) * 0.85}%"}></i>
          <span>{row.text}</span>
        </span>
      </li>
    </ul>
    """
  end

  attr :ticks, :list, required: true
  attr :top, :integer, required: true
  attr :format, :any, default: &Integer.to_string/1

  defp ticks(assigns) do
    ~H"""
    <div :for={tick <- @ticks} class="chart-tick" style={"bottom: #{percent(tick, @top)}%"}>
      <span>{@format.(tick)}</span>
    </div>
    """
  end

  defp scale(assigns) do
    ~H"""
    <div class="chart-scale" aria-hidden="true">
      <span>Fewer</span>
      <i :for={level <- 0..4} class={"shade-#{level}"}></i>
      <span>More</span>
    </div>
    """
  end

  @doc """
  Round tick values from 0 to at least `max`: `{top, ticks}`, with 3 to 5 ticks on 1, 2,
  or 5 times a power of ten.
  """
  def nice_ticks(max) when max <= 0, do: {4, [0, 2, 4]}

  def nice_ticks(max) do
    raw = max / 4
    magnitude = :math.pow(10, Float.floor(:math.log10(raw)))
    step = max(1, round(Enum.find([1, 2, 5, 10], &(&1 * magnitude >= raw)) * magnitude))
    top = ceil(max / step) * step
    {top, Enum.to_list(0..top//step)}
  end

  defp percent(_value, 0), do: 0
  defp percent(value, top), do: Float.round(value / top * 100, 2)

  defp svg_points(points), do: Enum.map_join(points, " ", fn {x, y} -> "#{x},#{y}" end)

  defp area_points([]), do: ""

  defp area_points(points) do
    {first_x, _} = List.first(points)
    {last_x, _} = List.last(points)
    svg_points(points) <> " #{last_x},100 #{first_x},100"
  end

  defp pad_hour(hour), do: hour |> Integer.to_string() |> String.pad_leading(2, "0")
end

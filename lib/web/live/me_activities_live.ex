defmodule Web.MeActivitiesLive do
  use Web, {:live_view_app_layout, access: :member, view_events: ["year"]}

  import Web.Components.ActivityMap
  import Web.Components.Chart, only: [bar_list: 1, column_chart: 1, sparkline: 1, stat: 1]
  import Web.Components.MeYear
  import Web.Components.MemberLetter

  alias App.Model.Activity
  alias App.Model.TaxCreditLetter
  alias App.ViewData.MemberRecords
  alias App.ViewData.MemberYear
  alias App.ViewData.TeamDashboardCharts
  alias Service.Format
  alias Web.Components.ActivityMap

  # The year page (#339, #406, #576), /teams/:subdomain/me/activities?year=2025: a
  # member's year. Its primary, secondary, and other hours and hours by month, its tax
  # credit letter and where they went, then its numbers against the year before over
  # every activity they attended. On a phone the letter comes first. `current_member` comes from the login, never
  # the URL.
  def mount(_params, _session, socket) do
    member = socket.assigns.current_member
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(member: member, team: member.team, now: now)
      |> assign(:this_year, Service.YearRange.year_in(now, member.team.timezone))
      |> assign(:years, MemberRecords.years_on_team(member, now))
      |> assign(:hours_tags, Activity.hours_tags(member.team))
      |> assign(:letters, TaxCreditLetter.get_all_for_member(member))

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    %{member: member, years: years, now: now} = socket.assigns
    year = year!(params["year"], years)
    attendances = MemberRecords.attendances(member, year, now)

    socket =
      socket
      |> assign(:page_title, "Your activities in #{year}")
      |> assign(:year, year)
      |> assign(:attendances, attendances)
      |> assign(:letter, Enum.find(socket.assigns.letters, &(&1.year == year)))
      |> assign(:map, where_they_went(attendances, member.team, now))
      |> assign_numbers(year, attendances)

    {:noreply, socket}
  end

  # The hours bars, and the year against the year before.
  defp assign_numbers(socket, year, attendances) do
    %{member: member, now: now, hours_tags: hours_tags} = socket.assigns
    tz = member.team.timezone
    before = MemberRecords.attendances(member, year - 1, now)
    hours = MemberYear.hours(attendances, year, tz, hours_tags)

    assign(socket,
      bars: bars(hours, MemberRecords.other_minutes(attendances, hours_tags)),
      summary: MemberYear.summary(attendances, before, year, now, tz, hours_tags)
    )
  end

  def handle_event("year", %{"year" => year}, socket),
    do:
      {:noreply,
       push_patch(socket, to: ~p"/teams/#{socket.assigns.team}/me/activities?year=#{year}")}

  # The Dashboard's map, with only the activities the member attended that year.
  defp where_they_went(attendances, team, now) do
    attendances
    |> Enum.map(& &1.activity)
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(fn activity ->
      %{
        title: activity.title,
        kind: TeamDashboardCharts.kind(activity.activity_kind),
        started_at: activity.started_at,
        coordinate: activity.coordinate
      }
    end)
    |> TeamDashboardCharts.map_points(team, now)
    |> ActivityMap.build({520, 380}, padding: 24)
  end

  # Other only when the year has some: most teams tag everything primary or secondary.
  defp bars(hours, other) do
    for {label, minutes} <- [
          {"Primary", hours.primary_minutes},
          {"Secondary", hours.secondary_minutes},
          {"Other", other}
        ],
        label != "Other" or minutes > 0,
        do: %{label: label, value: minutes, text: Format.duration(minutes)}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@team}/me"} />
      <:item label="Activities" />
    </.breadcrumbs>
    <h1 class="title">Your activities in {@year}</h1>
    <.year_menu years={@years} year={@year} />

    <div class="card-grid year-grid mt-6">
      <div class="card-stack span-7">
        <section id="hours" class="card">
          <header>
            <h2 class="chart-title">Hours in {@year}</h2>
          </header>
          <.bar_list id="hours-bars" rows={@bars} />
        </section>
        <section :if={@attendances != []} id="hours-by-month" class="card">
          <header>
            <h2 class="chart-title">Hours by month</h2>
          </header>
          <.column_chart
            id="hours-by-month-chart"
            columns={@summary.hour_columns}
            series={TeamDashboardCharts.series()}
            height={160}
            caption={"Hours by month in #{@year}"}
          />
        </section>
      </div>
      <div class="card-stack span-5">
        <section :if={@letter || @year == @this_year} class="card side-card year-letter">
          <.member_letter id="letter" team={@team} letter={@letter} year={@year} />
        </section>
        <section :if={@map} id="where-you-went" class="card">
          <header>
            <h2 class="chart-title">Where you went in {@year}</h2>
          </header>
          <.activity_map
            id="year-map"
            map={@map}
            label={"Map of your activities in #{@year}"}
            overlay={false}
          />
        </section>
      </div>
    </div>

    <div :if={@attendances != []} id="year-stats" class="chart-stats">
      <.stat
        id="stat-total"
        value={Format.hours(@summary.total_minutes)}
        label="Total hours"
        delta={versus(@summary.versus.hours, @year, @this_year)}
      >
        <.sparkline values={@summary.monthly.hours} />
      </.stat>
      <.stat
        id="stat-activities"
        value={Format.number(@summary.activities)}
        label={Format.count(@summary.activities, one: "Activity", many: "Activities")}
        delta={versus(@summary.versus.activities, @year, @this_year)}
      >
        <.sparkline values={@summary.monthly.activities} />
      </.stat>
      <.stat
        id="stat-incidents"
        series={:incident}
        value={Format.number(@summary.incidents)}
        label={Format.count(@summary.incidents, one: "Incident", many: "Incidents")}
        delta={versus(@summary.versus.incidents, @year, @this_year)}
      >
        <.sparkline values={@summary.monthly.incidents} series={:incident} />
      </.stat>
    </div>

    <.empty_state :if={@attendances == []} id="no-attendance" title={"No activities in #{@year}"}>
      Activities you attend show here after SAR Duty refreshes.
    </.empty_state>
    <.table
      :if={@attendances != []}
      id="attendance"
      rows={@attendances}
      row_id={&"attendance-#{&1.id}"}
    >
      <:col :let={attendance} label="Date" class="w-px whitespace-nowrap">
        <.date_cell value={attendance.started_at} timezone={@team.timezone} />
      </:col>
      <:col :let={attendance} label="Activity">
        <.activity_cell activity={attendance.activity} team={@team} kind={false} />
      </:col>
      <:col :let={attendance} label="Kind" class="w-px whitespace-nowrap max-md:hidden">
        <.activity_kind_mark activity={attendance.activity} />
      </:col>
      <%!-- Which tax credit hours it counts as, before the hours, as on Activities. --%>
      <:col :let={attendance} label="Hours" align="right" class="w-px whitespace-nowrap">
        <span class="text-text-muted max-md:hidden">
          {hours_label(MemberRecords.hours_kind(attendance, @hours_tags))}
        </span>
        <.hours_cell minutes={MemberRecords.minutes(attendance)} />
      </:col>
    </.table>
    <p id="missing" class="hint mt-4">
      Missing an activity? Tell a team admin.
    </p>
    """
  end

  # "12 more than this time last year" for this year, "12 more than in 2024" for a past
  # one, as on the Dashboard.
  defp versus({now, before}, year, this_year) do
    than = if year == this_year, do: "this time last year", else: "in #{year - 1}"

    cond do
      now > before -> "#{Format.number(now - before)} more than #{than}"
      now < before -> "#{Format.number(before - now)} fewer than #{than}"
      year == this_year -> "Same as this time last year"
      true -> "Same as #{year - 1}"
    end
  end

  defp hours_label(:primary), do: "Primary"
  defp hours_label(:secondary), do: "Secondary"
  defp hours_label(:other), do: "Other"
end

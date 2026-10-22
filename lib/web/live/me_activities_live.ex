defmodule Web.MeActivitiesLive do
  use Web, {:live_view_app_layout, access: :member}

  import Web.Components.ActivityMap
  import Web.Components.Chart, only: [bar_list: 1]
  import Web.Components.MeYear
  import Web.Components.MemberLetter

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.TaxCreditLetter
  alias App.ViewData.MemberRecords
  alias App.ViewData.TeamDashboardCharts
  alias Service.Format
  alias Web.Components.ActivityMap

  # The year page (#339, #406), /teams/:subdomain/me/activities?year=2025: every activity
  # the member attended in a year, that year's tax credit letter, its primary, secondary,
  # and other hours, and where they went. `current_member` comes from the login, never
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
    %{member: member, years: years, now: now, hours_tags: hours_tags} = socket.assigns
    year = year!(params["year"], years)
    attendances = MemberRecords.attendances(member, year, now)
    hours = MemberRecords.hours(member, year, now)

    socket =
      socket
      |> assign(:page_title, "Your activities in #{year}")
      |> assign(:year, year)
      |> assign(:attendances, attendances)
      |> assign(:letter, Enum.find(socket.assigns.letters, &(&1.year == year)))
      |> assign(:bars, bars(hours, MemberRecords.other_minutes(attendances, hours_tags)))
      |> assign(:map, where_they_went(attendances, member.team, now))

    {:noreply, socket}
  end

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

  defp bars(hours, other) do
    for {label, minutes} <- [
          {"Primary", hours.primary_minutes},
          {"Secondary", hours.secondary_minutes},
          {"Other", other}
        ],
        do: %{label: label, value: minutes, text: Format.duration(minutes)}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@team}/me"} />
      <:item label="Activities" />
    </.breadcrumbs>
    <h1 class="title">Your activities in {@year}</h1>
    <.year_switch years={@years} year={@year} path={~p"/teams/#{@team}/me/activities"} />

    <div class="card-grid mt-6 mb-6">
      <div class={["card-stack", @map && "span-7"]}>
        <section :if={@letter || @year == @this_year} class="card side-card">
          <.member_letter id="letter" team={@team} letter={@letter} year={@year} />
        </section>
        <section id="hours" class="card">
          <header class="heading-row mb-2">
            <h2 class="chart-title">Hours in {@year}</h2>
            <span id="activity-count" class="hint">
              {Format.count(length(@attendances), one: "1 activity", many: "%d activities")}
            </span>
          </header>
          <.bar_list id="hours-bars" rows={@bars} />
        </section>
      </div>
      <section :if={@map} id="where-you-went" class="card span-5">
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

    <.empty_state :if={@attendances == []} id="no-attendance" title={"No activities in #{@year}"}>
      Activities you attend show here after SAR Duty refreshes from {D4H.service_name(@team)}.
    </.empty_state>
    <.table
      :if={@attendances != []}
      id="attendance"
      rows={@attendances}
      row_id={&"attendance-#{&1.id}"}
    >
      <:col :let={attendance} label="Date" class="w-px whitespace-nowrap">
        {Format.month_day(attendance.started_at, @team.timezone)}
      </:col>
      <:col :let={attendance} label="Activity">
        <.d4h_activity_link team={@team} activity={attendance.activity} />
      </:col>
      <:col :let={attendance} label="Kind" class="w-px whitespace-nowrap max-md:hidden">
        <.activity_kind_mark activity={attendance.activity} />
      </:col>
      <:col :let={attendance} label="Hours" class="w-px whitespace-nowrap max-md:hidden">
        {hours_label(MemberRecords.hours_kind(attendance, @hours_tags))}
      </:col>
      <:col :let={attendance} label="Time" align="right" class="w-px whitespace-nowrap">
        {Format.duration(MemberRecords.minutes(attendance))}
      </:col>
    </.table>
    <p id="missing" class="hint mt-4">
      Missing an activity? Tell a team admin, who can fix it in {D4H.service_name(@team)}.
    </p>
    """
  end

  defp hours_label(:primary), do: "Primary"
  defp hours_label(:secondary), do: "Secondary"
  defp hours_label(:other), do: "Other"
end

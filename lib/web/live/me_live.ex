defmodule Web.MeLive do
  use Web, :live_view_app_layout

  import Web.Components.ActivityMap
  import Web.Components.Chart
  import Web.Components.OpenInMaps

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Team
  alias App.ViewData.MemberOverview
  alias App.ViewData.MemberRecords
  alias App.ViewData.TeamDashboardCharts
  alias Service.Format
  alias Web.Components.ActivityMap

  # A member's overview (#389), /teams/:subdomain/me: their year at a glance, as the team
  # home is for team admins, built from the same parts. `member` comes from the login
  # (Web.UserAuth, :ensure_team_member), never from the URL. Mostly read on a phone.
  def mount(_params, _session, socket) do
    member = socket.assigns.member
    team = member.team
    now = DateTime.utc_now()

    overview =
      member
      |> MemberRecords.attended(now)
      |> MemberOverview.build(MemberRecords.qualifications(member, now), now, team.timezone)

    socket =
      socket
      |> assign(:page_title, member.name)
      |> assign(:now, now)
      |> assign(:has_logo, Team.logo_file(team.subdomain) != nil)
      |> assign(:next_up, member |> MemberRecords.signed_up(now) |> List.first())
      |> assign(:overview, overview)
      |> assign(:map, build_map(overview.last_12_months, team, now))

    {:ok, socket}
  end

  defp build_map(attendances, team, now) do
    attendances
    |> Enum.map(fn %{activity: activity} ->
      activity
      |> Map.take([:coordinate, :started_at, :title])
      |> Map.put(:kind, TeamDashboardCharts.kind(activity.activity_kind))
    end)
    |> TeamDashboardCharts.map_points(team, now)
    |> ActivityMap.build({520, 380}, padding: 24)
  end

  def render(assigns) do
    ~H"""
    <div class="heading-row team-heading">
      <div class="min-w-0">
        <h1 class="title-hero mb-0">{@member.name}</h1>
        <p id="member-since" class="hint mt-1">{since_line(@member, @now)}</p>
      </div>
      <img
        :if={@has_logo}
        id="team-logo"
        src={~p"/teams/#{@member.team}/logo?shape=square"}
        class="logo-lg"
        alt="Team logo"
      />
    </div>

    <.next_up
      :if={@next_up}
      team={@member.team}
      attendance={@next_up}
      maps_app={@current_user.maps_app}
      now={@now}
    />

    <.stats team={@member.team} overview={@overview} />

    <div class="card-grid">
      <section id="hours-by-kind" class="card span-7">
        <header>
          <h2 class="chart-title">Where your hours went</h2>
          <span class="hint">{@overview.year}</span>
        </header>
        <.bar_list
          :if={@overview.hours_by_kind != []}
          id="hours-by-kind-chart"
          rows={MemberOverview.bars(@overview.hours_by_kind)}
        />
        <p :if={@overview.hours_by_kind == []} id="hours-by-kind-chart" class="chart-caption">
          No activities in {@overview.year} yet.
        </p>
        <div class="mt-4">
          <p class="chart-caption mb-0">
            Every activity you attended counts here. Your tax credit letter counts only some: <.a navigate={
              ~p"/teams/#{@member.team}/me/hours"
            }>hours for your tax credit letter</.a>.
          </p>
        </div>
      </section>
      <section id="where-you-went" class="card span-5">
        <header>
          <h2 class="chart-title">Where you went</h2>
          <span class="hint">The last 12 months</span>
        </header>
        <.activity_map
          :if={@map}
          id="activity-map"
          map={@map}
          label="Map of your activities in the last 12 months"
          overlay={false}
        />
        <p :if={!@map} id="activity-map" class="chart-caption">
          No activities with a place in the last 12 months.
        </p>
      </section>
      <section id="lately" class="card">
        <header>
          <h2 class="chart-title">Lately</h2>
          <.a navigate={~p"/teams/#{@member.team}/me/activities"}>All your activities</.a>
        </header>
        <p :if={@overview.lately == []} id="lately-empty" class="chart-caption">
          No activities yet. Activities you attend show here after SAR Duty refreshes from {D4H.service_name(
            @member.team
          )}.
        </p>
        <.table
          :if={@overview.lately != []}
          id="lately-list"
          rows={@overview.lately}
          row_id={&"lately-list-#{&1.id}"}
        >
          <:col :let={attendance} label="Date" class="w-px whitespace-nowrap">
            {Format.date_short(attendance.started_at, @member.team.timezone)}
          </:col>
          <:col :let={attendance} label="Activity">
            <.d4h_activity_link team={@member.team} activity={attendance.activity} />
          </:col>
          <:col :let={attendance} label="Kind" class="w-px whitespace-nowrap max-sm:hidden">
            <.activity_kind_mark activity={attendance.activity} />
          </:col>
          <:col :let={attendance} label="Time" align="right" class="w-px whitespace-nowrap">
            {Format.duration(MemberRecords.minutes(attendance))}
          </:col>
        </.table>
      </section>
    </div>
    """
  end

  # "Member since May 2019 · Refreshed from D4H 7 min ago"
  defp since_line(member, now) do
    [
      member.joined_at &&
        "Member since #{Format.month_year(member.joined_at, member.team.timezone)}",
      refreshed_ago(member.team, now)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  attr :team, :map, required: true
  attr :attendance, :map, required: true
  attr :maps_app, :string, required: true
  attr :now, :any, required: true

  defp next_up(assigns) do
    assigns = assign(assigns, :activity, assigns.attendance.activity)

    ~H"""
    <section id="next-up" class="card next-up">
      <div class="next-up-when">
        <span class="hint">You're signed up</span>
        <span class="next-up-day">
          {Format.day_coming_up(@activity.started_at, @now, @team.timezone)}
        </span>
        <span class="next-up-time">{Format.time_short(@activity.started_at, @team.timezone)}</span>
      </div>
      <div class="min-w-0">
        <.activity_kind_mark activity={@activity} class="text-sm" />
        <h2 class="next-up-title">
          <.d4h_activity_link team={@team} activity={@activity} />
        </h2>
        <p class="hint">{where_and_when(@activity, @now)}</p>
        <.open_in_maps
          id="next-up-maps"
          app={@maps_app}
          coordinate={Activity.pin(@activity)}
          address={@activity.address}
          label={@activity.title}
        />
      </div>
      <.button
        id="next-up-calendar"
        href={~p"/teams/#{@team}/me/activities/#{@activity.id}/calendar"}
      >
        Add to calendar
      </.button>
    </section>
    """
  end

  # "Coast Range SAR hall · in 3 days", or the time alone when D4H has no place.
  defp where_and_when(activity, now) do
    [activity.address, Format.starts_in(activity.started_at, now)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  attr :team, :map, required: true
  attr :overview, :map, required: true

  defp stats(assigns) do
    ~H"""
    <div id="overview-stats" class="chart-stats">
      <.stat
        id="stat-hours"
        value={Format.hours(@overview.minutes)}
        label={"Hours in #{@overview.year}"}
        href={~p"/teams/#{@team}/me/hours"}
      />
      <.stat
        id="stat-activities"
        value={Format.number(@overview.activities)}
        label={"Activities in #{@overview.year}"}
        href={~p"/teams/#{@team}/me/activities"}
      />
      <.stat
        id="stat-incidents"
        series={:incident}
        value={Format.number(@overview.incidents)}
        label={"Incidents in #{@overview.year}"}
      />
      <.stat
        id="stat-qualifications"
        value={Format.number(@overview.qualifications.count)}
        label="Qualifications"
        href={~p"/teams/#{@team}/me/qualifications"}
        delta={next_to_expire(@overview.qualifications.next, @team.timezone)}
      />
    </div>
    """
  end

  defp next_to_expire(nil, _timezone), do: nil

  defp next_to_expire(award, timezone),
    do: "#{award.qualification.title} expires #{Format.date_long(award.ends_at, timezone)}"
end

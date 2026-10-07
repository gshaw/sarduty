defmodule Web.TeamDashboardLive do
  use Web, :live_view_app_layout

  import Web.Components.ActivityMap
  import Web.Components.Chart

  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.ViewData.TeamDashboardCharts
  alias App.ViewData.TeamDashboardViewData
  alias App.Worker.RefreshTeamDataWorker
  alias App.Worker.SyncTeamChangesWorker
  alias Service.Format
  alias Web.Components.ActivityMap

  # The top half is what needs doing: what's next, and what needs a team admin. The lower
  # half is the team's year, loaded after it so the work never waits on the charts (#205).

  def mount(_params, _session, socket) do
    current_team = socket.assigns.current_team

    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")
      # Opening the dashboard catches up with D4H rather than waiting for the next sync.
      SyncTeamChangesWorker.enqueue_if_stale(current_team, DateTime.utc_now())
    end

    socket =
      socket
      |> assign(page_title: current_team.name)
      |> assign_page(current_team)

    {:ok, socket}
  end

  defp assign_page(socket, team), do: socket |> assign_top_half(team) |> assign_pulse(team)

  defp assign_top_half(socket, team) do
    now = DateTime.utc_now()

    socket
    |> assign(now: now)
    |> assign(view_data: TeamDashboardViewData.build(team, now))
    |> assign(has_logo: Team.logo_file(team.subdomain) != nil)
  end

  defp assign_pulse(socket, team) do
    assign_async(socket, :pulse, fn -> {:ok, %{pulse: build_pulse(team)}} end, reset: false)
  end

  defp build_pulse(team) do
    charts = team |> TeamDashboardViewData.chart_rows() |> TeamDashboardCharts.shape(team)
    %{charts: charts, map: ActivityMap.build(charts.map_points, {520, 380}, padding: 24)}
  end

  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4 mb-p">
      <div class="min-w-0">
        <h1 class="title-hero mb-0">{@current_team.name}</h1>
        <.refresh_line team={@current_team} view_data={@view_data} now={@now} />
      </div>
      <img
        :if={@has_logo}
        id="team-logo"
        src={~p"/teams/#{@current_team}/logo?shape=square"}
        class="h-24"
        alt="Team logo"
      />
    </div>

    <.next_up
      :if={@view_data.next_up}
      team={@current_team}
      activity={@view_data.next_up}
      now={@now}
    />

    <div class="dash-grid">
      <.coming_up team={@current_team} activities={@view_data.coming_up} now={@now} />
      <.needs_attention team={@current_team} items={@view_data.attention} />
    </div>

    <.async_result :let={pulse} assign={@pulse}>
      <:loading>
        <p id="pulse-loading" class="chart-caption">Drawing the charts…</p>
      </:loading>
      <:failed>
        <p id="pulse-failed" class="chart-caption">
          The charts cannot load. Reload the page.
        </p>
      </:failed>
      <.pulse team={@current_team} charts={pulse.charts} map={pulse.map} />
    </.async_result>
    """
  end

  attr :team, :map, required: true
  attr :view_data, :map, required: true
  attr :now, :any, required: true

  # Two lines that keep their size while a refresh runs, so nothing under them moves: what
  # SAR Duty last did, cut to one line, then the links, which stay put. Refresh now is
  # disabled while a refresh runs rather than hidden.
  defp refresh_line(assigns) do
    assigns = assign(assigns, :refreshing?, refreshing?(assigns.view_data))

    ~H"""
    <div class="text-sm text-secondary-1 mt-1">
      <p id="refresh-status" class="mb-0 truncate">
        <span :if={@refreshing?} id="refreshing" class="text-primary-1">
          <span class="inline-block h-3 w-3 animate-spin rounded-full border-2 border-current border-t-transparent align-[-1px] mr-1"></span>
          {refreshing_text(@view_data.refresh_result)}
        </span>
        <span :if={!@refreshing?} id="d4h-updated">{refreshed_ago(@team, @now)}</span>
      </p>
      <p class="mb-0 flex items-center gap-3">
        <button
          id="refresh-now"
          type="button"
          phx-click="refresh"
          disabled={@refreshing?}
          class="text-primary-1 underline disabled:no-underline disabled:text-secondary-1 disabled:cursor-default"
        >
          Refresh now
        </button>
        <span aria-hidden="true">·</span>
        <.a external={true} href={D4H.build_url(@team, "/dashboard")}>Open D4H</.a>
      </p>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :activity, :map, required: true
  attr :now, :any, required: true

  defp next_up(assigns) do
    ~H"""
    <section id="next-up" class="dash-card next-up">
      <div class="next-up-when">
        <span class="text-sm text-secondary-1">Next up</span>
        <span class="next-up-day">
          {Format.day_coming_up(@activity.started_at, @now, @team.timezone)}
        </span>
        <span class="next-up-time">{Format.time_short(@activity.started_at, @team.timezone)}</span>
      </div>
      <div class="min-w-0">
        <.kind activity={@activity} />
        <h2 class="next-up-title">
          <.a navigate={~p"/teams/#{@team}/activities/#{@activity.id}"}>{@activity.title}</.a>
        </h2>
        <p class="text-sm text-secondary-1">{where_and_when(@activity, @now)}</p>
      </div>
      <.button
        id="next-up-take-attendance"
        variant={:primary}
        navigate={~p"/teams/#{@team}/activities/#{@activity.id}/take-attendance"}
      >
        Take attendance
      </.button>
    </section>
    """
  end

  # "Murrin Park · in 3 hours", or the time alone when D4H has no place.
  defp where_and_when(activity, now) do
    [activity.address, Format.starts_in(activity.started_at, now)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  attr :team, :map, required: true
  attr :activities, :list, required: true
  attr :now, :any, required: true

  defp coming_up(assigns) do
    ~H"""
    <section id="coming-up" class="dash-card span-6">
      <header>
        <h2 class="chart-title">Coming up</h2>
        <span class="text-sm text-secondary-1">Next 14 days</span>
      </header>
      <p :if={@activities == []} id="coming-up-empty" class="chart-caption">
        No activities planned in D4H.
      </p>
      <ul :if={@activities != []} id="coming-up-list" class="dash-rows">
        <li :for={activity <- @activities} id={"coming-up-#{activity.id}"}>
          <span class="dash-row-when">
            <strong>{Format.day_coming_up(activity.started_at, @now, @team.timezone)}</strong>
            <span class="text-secondary-1">{Format.time_short(activity.started_at, @team.timezone)}</span>
          </span>
          <span class="dash-row-title">
            <.kind activity={activity} />
            <.a navigate={~p"/teams/#{@team}/activities/#{activity.id}"}>{activity.title}</.a>
          </span>
          <.button
            size={:sm}
            navigate={~p"/teams/#{@team}/activities/#{activity.id}/take-attendance"}
          >
            Take attendance
          </.button>
        </li>
      </ul>
      <footer>
        <.a navigate={~p"/teams/#{@team}/activities?when=future&sort=date"}>
          All future activities
        </.a>
      </footer>
    </section>
    """
  end

  attr :team, :map, required: true
  attr :items, :list, required: true

  defp needs_attention(assigns) do
    ~H"""
    <section id="needs-attention" class="dash-card span-6">
      <header>
        <h2 class="chart-title">Needs attention</h2>
      </header>
      <p :if={@items == []} id="needs-attention-empty" class="chart-caption">
        Nothing needs you right now.
      </p>
      <ul :if={@items != []} id="needs-attention-list" class="dash-rows attention">
        <li :for={item <- @items} id={"attention-#{item.key}"} class={"is-#{item.level}"}>
          <span class="attention-mark" aria-hidden="true"></span>
          <span class="dash-row-title">
            <strong>{item.title}</strong>
            <span :if={item.detail} class="text-sm text-secondary-1">{item.detail}</span>
          </span>
          <.button size={:sm} navigate={attention_path(@team, item)}>{item.action}</.button>
        </li>
      </ul>
    </section>
    """
  end

  defp attention_path(team, %{key: :refresh}), do: ~p"/teams/#{team}/settings"

  defp attention_path(team, %{key: :drafts}),
    do: ~p"/teams/#{team}/activities?status=draft&when=recent&sort=date-"

  defp attention_path(team, %{key: :expiring}),
    do: ~p"/teams/#{team}/qualifications?view=expiring"

  defp attention_path(team, %{key: :missing_details}),
    do: ~p"/teams/#{team}/members?details=missing"

  defp attention_path(team, %{key: :group_changes}), do: ~p"/teams/#{team}/groups"

  defp attention_path(team, %{key: :proposed_changes}),
    do: ~p"/teams/#{team}/proposed-changes"

  defp attention_path(team, %{key: :letters, year: year}),
    do: ~p"/teams/#{team}/tax-credit-letters?year=#{year}"

  attr :activity, :map, required: true

  defp kind(assigns) do
    ~H"""
    <span class={["activity-kind", "activity-kind-#{@activity.activity_kind}", "text-sm"]}>
      {String.capitalize(@activity.activity_kind)}
    </span>
    """
  end

  attr :team, :map, required: true
  attr :charts, :map, required: true
  attr :map, :map, default: nil

  defp pulse(assigns) do
    ~H"""
    <div id="team-pulse">
      <div class="chart-stats">
        <.stat
          id="stat-activities"
          value={Format.number(@charts.activities_ytd)}
          label={"Activities in #{@charts.year}"}
          href={~p"/teams/#{@team}/activities?when=past&sort=date-"}
          delta={versus(@charts.activities_ytd, @charts.activities_last_ytd)}
        >
          <.sparkline values={@charts.monthly_activities} />
        </.stat>
        <.stat
          id="stat-incidents"
          series={:incident}
          value={Format.number(@charts.incidents_ytd)}
          label={"Incidents in #{@charts.year}"}
          delta={versus(@charts.incidents_ytd, @charts.incidents_last_ytd)}
        >
          <.sparkline values={@charts.monthly_incidents} series={:incident} />
        </.stat>
        <.stat
          id="stat-hours"
          value={Format.hours(@charts.minutes_ytd)}
          label={"Member hours in #{@charts.year}"}
          delta={versus(div(@charts.minutes_ytd, 60), div(@charts.minutes_last_ytd, 60), "h")}
        >
          <.sparkline values={@charts.monthly_hours} />
        </.stat>
        <.stat
          id="stat-members"
          value={Format.number(@charts.members)}
          label="Current members"
          href={~p"/teams/#{@team}/members"}
          delta={"#{@charts.members_joined} joined in #{@charts.year}"}
        />
      </div>
      <div class="dash-grid">
        <section class="dash-card span-7">
          <header>
            <h2 class="chart-title">Activities by month</h2>
            <.a navigate={~p"/teams/#{@team}/activities?when=past&sort=date-"}>All activities</.a>
          </header>
          <p class="chart-caption">The last 12 months</p>
          <.column_chart
            id="activities-by-month"
            columns={@charts.activity_columns}
            series={TeamDashboardCharts.series()}
            caption="Activities by month"
          />
        </section>
        <section class="dash-card span-5">
          <header>
            <h2 class="chart-title">Where the team went</h2>
          </header>
          <p :if={@map} class="chart-caption">
            The last 12 months. Large dots are the last 30 days.
          </p>
          <.activity_map
            :if={@map}
            id="activity-map"
            map={@map}
            label="Map of activities in the last 12 months"
            overlay={false}
          />
          <p :if={!@map} id="activity-map" class="chart-caption">
            No activities with a place in D4H in the last 12 months.
          </p>
        </section>
        <section class="dash-card">
          <header>
            <h2 class="chart-title">Every day out</h2>
          </header>
          <p class="chart-caption">The last 12 months</p>
          <div class="dash-scroll">
            <.calendar id="activity-calendar" days={@charts.calendar_days} />
          </div>
        </section>
      </div>
    </div>
    """
  end

  # Against the same days of last year: "12 more than this time last year".
  defp versus(now, before, unit \\ "") do
    cond do
      now > before -> "#{Format.number(now - before)}#{unit} more than this time last year"
      now < before -> "#{Format.number(before - now)}#{unit} fewer than this time last year"
      true -> "Same as this time last year"
    end
  end

  # The refresh's own progress, such as "Members: 120/480 (25%)", after the slow thing.
  defp refreshing_text("Refreshing"), do: "Refreshing from D4H…"
  defp refreshing_text(stage), do: "Refreshing from D4H… #{stage}"

  # "Refreshed from D4H 7 min ago". Glossary: refresh, never update or sync.
  defp refreshed_ago(team, now) do
    case team |> Team.d4h_updated_at() |> Format.minutes_ago(now, team.timezone) do
      nil -> "Not refreshed from D4H yet"
      ago -> "Refreshed from D4H #{ago}"
    end
  end

  # Progress messages arrive at every stage of a full refresh; the page recounts once the
  # refresh or sync is done, not at each stage.
  def handle_info({:team_refreshed, %Team{} = updated_team}, socket) do
    if updated_team.id == socket.assigns.current_team.id do
      socket = assign(socket, current_team: updated_team)

      if Team.refresh_state(updated_team.d4h_refresh_result) == :refreshing do
        view_data = %{socket.assigns.view_data | refresh_result: updated_team.d4h_refresh_result}
        {:noreply, assign(socket, view_data: view_data)}
      else
        {:noreply, assign_page(socket, updated_team)}
      end
    else
      {:noreply, socket}
    end
  end

  # A second refresh while one runs does nothing; the button is disabled, but a page open
  # in 2 tabs can still send one.
  def handle_event("refresh", _params, socket) do
    if refreshing?(socket.assigns.view_data),
      do: {:noreply, socket},
      else: start_refresh(socket)
  end

  defp start_refresh(socket) do
    %{team_id: socket.assigns.current_team.id}
    |> RefreshTeamDataWorker.new()
    |> Oban.insert()

    view_data = %{socket.assigns.view_data | refresh_result: "Refreshing"}

    {:noreply, assign(socket, view_data: view_data)}
  end

  defp refreshing?(view_data), do: Team.refresh_state(view_data.refresh_result) == :refreshing
end

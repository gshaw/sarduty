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
      |> assign_top_half(current_team)
      |> assign_pulse(current_team)

    {:ok, socket}
  end

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
      <div>
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
        <p id="pulse-loading" class="chart-caption">Drawing the team's year…</p>
      </:loading>
      <:failed>
        <p id="pulse-failed" class="chart-caption">
          The team's year cannot be drawn right now. Reload the page to try again.
        </p>
      </:failed>
      <.pulse team={@current_team} charts={pulse.charts} map={pulse.map} />
    </.async_result>
    """
  end

  attr :team, :map, required: true
  attr :view_data, :map, required: true
  attr :now, :any, required: true

  defp refresh_line(assigns) do
    ~H"""
    <div class="text-sm text-secondary-1 flex flex-wrap items-center gap-x-3 gap-y-1 mt-1">
      <%= if refreshing?(@view_data) do %>
        <span id="refreshing" class="flex items-center gap-2 text-primary-1">
          <span class="inline-block h-3 w-3 animate-spin rounded-full border-2 border-current border-t-transparent"></span>
          {@view_data.refresh_result}
        </span>
      <% else %>
        <span id="d4h-updated">
          Updated from D4H {Format.minutes_ago(Team.d4h_updated_at(@team), @now, @team.timezone) ||
            "never"}
        </span>
        <span aria-hidden="true">·</span>
        <button id="refresh-now" type="button" phx-click="refresh" class="text-primary-1 underline">
          Refresh now
        </button>
      <% end %>
      <span aria-hidden="true">·</span>
      <.a external={true} href={D4H.build_url(@team, "/dashboard")}>Open D4H</.a>
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
        No activities planned in D4H for the next 14 days.
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
            <span class="text-sm text-secondary-1">{item.detail}</span>
          </span>
          <.button size={:sm} navigate={attention_path(@team, item)}>{item.action}</.button>
        </li>
      </ul>
    </section>
    """
  end

  defp attention_path(team, %{key: :refresh}), do: ~p"/teams/#{team}/settings"

  defp attention_path(team, %{key: :drafts}),
    do: ~p"/teams/#{team}/activities?status=draft&when=past&sort=date-"

  defp attention_path(team, %{key: :expiring}),
    do: ~p"/teams/#{team}/qualifications?view=expiring"

  defp attention_path(team, %{key: :missing_details}),
    do: ~p"/teams/#{team}/members?details=missing"

  defp attention_path(team, %{key: :group_changes}), do: ~p"/teams/#{team}/groups"

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
          label="Incidents"
          delta={versus(@charts.incidents_ytd, @charts.incidents_last_ytd)}
        >
          <.sparkline values={@charts.monthly_incidents} series={:incident} />
        </.stat>
        <.stat
          id="stat-hours"
          value={Format.hours(@charts.minutes_ytd)}
          label="Member hours"
          delta={versus(div(@charts.minutes_ytd, 60), div(@charts.minutes_last_ytd, 60))}
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
          <p class="chart-caption">Activities in the last 12 months. Large dots are this month.</p>
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
          <p class="chart-caption">Activities on each day of the last 12 months</p>
          <.calendar id="activity-calendar" days={@charts.calendar_days} />
        </section>
      </div>
    </div>
    """
  end

  # Against the same days of last year.
  defp versus(now, before) do
    cond do
      now > before -> "Up #{Format.number(now - before)} on this time last year"
      now < before -> "Down #{Format.number(before - now)} on this time last year"
      true -> "Same as this time last year"
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
        {:noreply, socket |> assign_top_half(updated_team) |> assign_pulse(updated_team)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh", _params, socket) do
    %{team_id: socket.assigns.current_team.id}
    |> RefreshTeamDataWorker.new()
    |> Oban.insert()

    view_data = %{socket.assigns.view_data | refresh_result: "Refreshing"}

    {:noreply, assign(socket, view_data: view_data)}
  end

  defp refreshing?(view_data), do: Team.refresh_state(view_data.refresh_result) == :refreshing
end

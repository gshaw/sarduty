defmodule Web.TeamDashboardLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.ViewData.TeamDashboardViewData
  alias App.Worker.RefreshTeamDataWorker
  alias App.Worker.SyncTeamChangesWorker

  def mount(_params, _session, socket) do
    current_team = socket.assigns.current_team

    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")
      # Opening the dashboard catches up with D4H rather than waiting for the next sync.
      SyncTeamChangesWorker.enqueue_if_stale(current_team, DateTime.utc_now())
    end

    view_data = TeamDashboardViewData.build(current_team)

    socket =
      socket
      |> assign(page_title: current_team.name)
      |> assign(view_data: view_data)
      |> assign(now: DateTime.utc_now())
      |> assign(has_logo: Team.logo_file(current_team.subdomain) != nil)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title-hero mb-p flex items-center justify-between">
      {@current_team.name}
      <img
        :if={@has_logo}
        id="team-logo"
        src={~p"/teams/#{@current_team}/logo?shape=square"}
        class="h-32"
        alt="Team logo"
      />
    </h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content team={@current_team} view_data={@view_data} now={@now} />
      </aside>
      <main class="content-2/3">
        <.main_content team={@current_team} />
      </main>
    </div>
    """
  end

  def main_content(assigns) do
    ~H"""
    <ul class="action-list">
      <li class="heading">
        <.a navigate={~p"/teams/#{@team}/activities"}>Activities</.a>

        <ul class="subheading action-list ml-hindent">
          <li>
            <.a navigate={~p"/teams/#{@team}/activities?&when=future&sort=date"}>
              Future
            </.a>
          </li>
          <li>
            <.a navigate={~p"/teams/#{@team}/activities?when=past&sort=date-"}>
              Past
            </.a>
          </li>
        </ul>
      </li>
      <li class="heading">
        <.a navigate={~p"/teams/#{@team}/members"}>Members</.a>
        <ul class="subheading action-list ml-hindent">
          <li>
            <.a navigate={~p"/teams/#{@team}/settings/managers"}>Managers</.a>
          </li>
          <li>
            <.a navigate={~p"/teams/#{@team}/groups"}>Groups</.a>
          </li>
          <li>
            <.a navigate={~p"/teams/#{@team}/qualifications"}>Qualifications</.a>
          </li>
          <li>
            <.a navigate={~p"/teams/#{@team}/tax-credit-letters"}>Tax credit letters</.a>
          </li>
        </ul>
      </li>
    </ul>
    """
  end

  def sidebar_content(assigns) do
    ~H"""
    <dl>
      <dt>Actions</dt>
      <dd class="border-b-0">
        <div class="mb-p">
          <.a external={true} href={D4H.build_url(@team, "/dashboard")}>Open D4H dashboard</.a>
        </div>
        <%= if refreshing?(@view_data) do %>
          <div class="flex items-center gap-2 text-primary-1">
            <span class="inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"></span>
            <span>{@view_data.refresh_result}</span>
          </div>
        <% else %>
          <.button
            type="button"
            variant={:warning}
            phx-click="refresh"
            disabled={refreshing?(@view_data)}
          >
            Refresh from D4H
          </.button>
        <% end %>
      </dd>

      <dt>Updated from D4H</dt>
      <dd id="d4h-updated">
        {Service.Format.minutes_ago(Team.d4h_updated_at(@team), @now, @team.timezone) ||
          "Never"}
      </dd>
      <dt>Last full refresh</dt>
      <dd>
        {Service.Format.datetime_short(@view_data.refreshed_at, @team.timezone)}
        <div :if={failed?(@view_data)} id="refresh-error" class="text-sm text-danger-1">
          {String.replace_prefix(@view_data.refresh_result, "Error: ", "")}
        </div>
      </dd>
      <dt>Members</dt>
      <dd>{@view_data.member_count}</dd>
      <dt>Activities</dt>
      <dd>{@view_data.activity_count}</dd>
      <dt>Attendances</dt>
      <dd>{@view_data.attendance_count}</dd>
      <dt>Qualifications</dt>
      <dd>{@view_data.qualification_count}</dd>
      <dt>Qualification awards</dt>
      <dd>{@view_data.qualification_award_count}</dd>
      <dt>Groups</dt>
      <dd>{@view_data.group_count}</dd>
      <dt>Group members</dt>
      <dd>{@view_data.group_member_count}</dd>
    </dl>
    """
  end

  def handle_info({:team_refreshed, updated_team}, socket) do
    if updated_team.id == socket.assigns.current_team.id do
      view_data =
        socket.assigns.view_data
        |> Map.put(:refreshed_at, updated_team.d4h_refreshed_at)
        |> Map.put(:refresh_result, updated_team.d4h_refresh_result)

      {:noreply,
       socket
       |> assign(current_team: updated_team)
       |> assign(now: DateTime.utc_now())
       |> assign(view_data: view_data)
       |> assign(has_logo: Team.logo_file(updated_team.subdomain) != nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh", _params, socket) do
    %{team_id: socket.assigns.current_team.id}
    |> RefreshTeamDataWorker.new()
    |> Oban.insert()

    view_data = Map.put(socket.assigns.view_data, :refresh_result, "Refreshing")

    {:noreply, assign(socket, view_data: view_data)}
  end

  defp refreshing?(view_data), do: Team.refresh_state(view_data.refresh_result) == :refreshing
  defp failed?(view_data), do: Team.refresh_state(view_data.refresh_result) == :failed
end

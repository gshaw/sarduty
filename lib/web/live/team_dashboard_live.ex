defmodule Web.TeamDashboardLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.ViewData.TeamDashboardViewData
  alias App.Worker.RefreshTeamDataWorker

  def mount(_params, _session, socket) do
    current_team = socket.assigns.current_team
    view_data = TeamDashboardViewData.build(current_team)

    socket =
      socket
      |> assign(page_title: current_team.name)
      |> assign(view_data: view_data)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title-hero mb-p flex items-center justify-between">
      {@current_team.name}
      <img src={~p"/#{@current_team.subdomain}/image"} class="h-32" alt="Team logo" />
    </h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content team={@current_team} view_data={@view_data} />
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
        <.a navigate={~p"/#{@team.subdomain}/activities"}>Activities</.a>

        <ul class="subheading action-list ml-hindent">
          <li>
            <.a navigate={~p"/#{@team.subdomain}/activities?&when=future&sort=date"}>
              Future
            </.a>
          </li>
          <li>
            <.a navigate={~p"/#{@team.subdomain}/activities?when=past&sort=date-"}>
              Past
            </.a>
          </li>
        </ul>
      </li>
      <li class="heading">
        <.a navigate={~p"/#{@team.subdomain}/members"}>Members</.a>
        <ul class="subheading action-list ml-hindent">
          <li>
            <.a navigate={~p"/#{@team.subdomain}/tax-credit-letters"}>Tax Credit Letters</.a>
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
          <.a external={true} href={D4H.build_url(@team, "/dashboard")}>Open D4H Dashboard</.a>
        </div>
        <%= if @view_data.refresh_result != "refreshing" do %>
          <.button type="button" class="btn-warning" phx-click="refresh">
            Refresh D4H Data
          </.button>
        <% end %>
      </dd>

      <dt>Last Refreshed</dt>
      <dd>
        {Service.Format.short_datetime(@view_data.refreshed_at, @team.timezone)}
        <%= if @view_data.refresh_result == "refreshing" do %>
          <span class="ml-2 text-sm text-amber-600 animate-pulse">Refreshing…</span>
        <% else %>
          <%= if @view_data.refresh_result && @view_data.refresh_result != "ok" do %>
            <span class="ml-2 text-sm text-red-600" title={@view_data.refresh_result}>Error</span>
          <% end %>
        <% end %>
      </dd>
      <dt>Members</dt>
      <dd>{@view_data.member_count}</dd>
      <dt>Activities</dt>
      <dd>{@view_data.activity_count}</dd>
      <dt>Attendances</dt>
      <dd>{@view_data.attendance_count}</dd>
      <dt>Qualifications</dt>
      <dd>{@view_data.qualification_count}</dd>
      <dt>Qualification Awards</dt>
      <dd>{@view_data.qualification_award_count}</dd>
    </dl>
    """
  end

  def handle_event("refresh", _params, socket) do
    %{team_id: socket.assigns.current_team.id}
    |> RefreshTeamDataWorker.new()
    |> Oban.insert()

    view_data = Map.put(socket.assigns.view_data, :refresh_result, "refreshing")

    {:noreply,
     socket
     |> assign(view_data: view_data)
     |> put_flash(:info, "D4H data refresh has been scheduled.")}
  end
end

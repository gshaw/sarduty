defmodule Web.TeamDashboardLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.ViewData.TeamDashboardViewData
  alias App.Worker.RefreshTeamDataWorker

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")

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
            <.a navigate={~p"/#{@team.subdomain}/qualifications"}>Qualifications</.a>
          </li>
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
        <%= if refreshing?(@view_data) do %>
          <div class="flex items-center gap-2 text-blue-600">
            <span class="inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent">
            </span>
            <span>{@view_data.refresh_result}</span>
          </div>
        <% else %>
          <.button
            type="button"
            class="btn-warning"
            phx-click="refresh"
            disabled={refreshing?(@view_data)}
          >
            Refresh D4H Data
          </.button>
        <% end %>
      </dd>

      <dt>Last Refreshed</dt>
      <dd>
        {Service.Format.short_datetime(@view_data.refreshed_at, @team.timezone)}
        <%= if @view_data.refresh_result && !refreshing?(@view_data) && @view_data.refresh_result != "OK" do %>
          <span class="ml-2 text-sm text-red-600" title={@view_data.refresh_result}>Error</span>
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

  def handle_info({:team_refreshed, updated_team}, socket) do
    if updated_team.id == socket.assigns.current_team.id do
      view_data =
        socket.assigns.view_data
        |> Map.put(:refreshed_at, updated_team.d4h_refreshed_at)
        |> Map.put(:refresh_result, updated_team.d4h_refresh_result)

      {:noreply,
       socket
       |> assign(current_team: updated_team)
       |> assign(view_data: view_data)}
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

  @refresh_stages [
    "Starting",
    "Team logo",
    "Members",
    "Tags",
    "Exercises",
    "Events",
    "Incidents",
    "Attendances",
    "Qualifications",
    "Qualification Awards"
  ]

  defp refreshing?(view_data) do
    result = view_data.refresh_result || ""
    result == "Refreshing" or Enum.any?(@refresh_stages, &String.contains?(result, &1))
  end
end

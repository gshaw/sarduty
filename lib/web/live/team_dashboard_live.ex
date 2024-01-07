defmodule Web.TeamDashboardLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Operation.RefreshD4HData
  alias App.ViewData.TeamDashboardViewData

  def mount(_params, _session, socket) do
    current_team = socket.assigns.current_team
    view_data = TeamDashboardViewData.build(current_team)

    socket =
      socket
      |> assign(page_title: current_team.name)
      |> assign(view_data: AsyncResult.ok(view_data))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title-hero mb-p"><%= @current_team.name %></h1>
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
        <.a external={true} href={D4H.build_url(@team, "/dashboard")}>Open D4H Dashboard</.a>
      </li>
      <li class="heading">
        Activities
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
          <li>
            <.a navigate={~p"/#{@team.subdomain}/activities"}>
              All
            </.a>
          </li>
        </ul>
      </li>
      <li class="heading">
        <.a navigate={~p"/#{@team.subdomain}/members"}>Members</.a>
      </li>
    </ul>
    """
  end

  def sidebar_content(assigns) do
    ~H"""
    <p>
      <.button
        type="button"
        class="btn-warning"
        phx-click="refresh"
        disabled={@view_data.loading != nil}
      >
        Refresh D4H Data
      </.button>
    </p>
    <.async_result :let={view_data} assign={@view_data}>
      <:loading>
        <.spinner>
          Refreshing D4H data...
          <div class="hint">This can take a few minutes</div>
        </.spinner>
      </:loading>
      <:failed :let={_reason}>There was an error refershing D4H data</:failed>

      <dl>
        <dt>Members</dt>
        <dd><%= view_data.member_count %></dd>

        <dt>Activities</dt>
        <dd><%= view_data.activity_count %></dd>

        <dt>Attendances</dt>
        <dd><%= view_data.attendance_count %></dd>

        <dt>Refreshed</dt>
        <dd>
          <%= Service.Format.short_datetime(view_data.refreshed_at, @team.timezone) %>
        </dd>
      </dl>
    </.async_result>
    """
  end

  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(view_data: nil)
      |> assign_async(:view_data, fn ->
        team = RefreshD4HData.call(socket.assigns.current_user)
        view_data = TeamDashboardViewData.build(team)
        {:ok, %{view_data: view_data}}
      end)

    {:noreply, socket}
  end
end

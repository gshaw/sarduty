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
    <h1 class="title-hero"><%= @current_team.name %></h1>

    <ul class="my-p2 action-list">
      <li class="heading">
        <.a external={true} href={D4H.build_url(@current_team, "/dashboard")}>Open D4H Dashboard</.a>
      </li>
      <li class="heading">
        <.a navigate={~p"/#{@current_team.subdomain}/activities"}>Activities</.a>
      </li>
      <li class="heading">
        <.a navigate={~p"/#{@current_team.subdomain}/members"}>Members</.a>
      </li>
    </ul>

    <p class="">
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
        <.spinner>Refreshing D4H data...</.spinner>
      </:loading>
      <:failed :let={_reason}>There was an error refershing D4H data</:failed>

      <table class="table">
        <tbody>
          <tr>
            <th>Members</th>
            <td class="text-right"><%= view_data.member_count %></td>
          </tr>
          <tr>
            <th>Activities</th>
            <td class="text-right"><%= view_data.activity_count %></td>
          </tr>
          <tr>
            <th>Attendances</th>
            <td class="text-right"><%= view_data.attendance_count %></td>
          </tr>
        </tbody>
      </table>
    </.async_result>
    """
  end

  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(view_data: nil)
      |> assign_async(:view_data, fn ->
        RefreshD4HData.call(socket.assigns.current_user)
        view_data = TeamDashboardViewData.build(socket.assigns.current_team)
        {:ok, %{view_data: view_data}}
      end)

    {:noreply, socket}
  end
end

defmodule Web.ActivityLive do
  use Web, :live_view_app

  import Web.WebComponents.A

  alias App.Adapter.D4H

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    activity_id = params["id"]
    d4h = D4H.build_context(socket.assigns.current_user)
    activity = D4H.fetch_activity(d4h, activity_id)

    {:noreply, assign(socket, activity: activity)}
  end

  def render(assigns) do
    ~H"""
    <div class="mb-p05 text-sm">
      <.a navigate={~p"/#{@current_team.subdomain}"}><%= @current_team.title %></.a>
      /
      <.a navigate={~p"/#{@current_team.subdomain}/activities/"}>Activities</.a>
      /
      #<%= @activity.activity_id %>
    </div>

    <h1 class="title"><%= @activity.title %></h1>
    <p><%= @activity.description %></p>
    <div class="mb-p">
      <h3 class="subheading">
        → <.a
          external={true}
          external_icon_class="w-6 h-6"
          href={
            D4H.build_team_manager_url(@current_team, "/team/exercises/view/#{@activity.activity_id}")
          }
          phx-no-format
        >Open D4H Activity</.a>
      </h3>
      <h3 class="subheading">
        →
        <.a navigate={~p"/#{@current_team.subdomain}/activities/#{@activity.activity_id}/attendance"}>
          Attendance
        </.a>
      </h3>
      <h3 class="subheading">
        →
        <.a navigate={~p"/#{@current_team.subdomain}/activities/#{@activity.activity_id}/mileage"}>
          Mileage Report
        </.a>
      </h3>
    </div>
    """
  end
end

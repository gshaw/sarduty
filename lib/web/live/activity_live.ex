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
      <.a navigate={~p"/southfrasersar"}>South Fraser SAR</.a>
      /
      <.a navigate={~p"/southfrasersar/activities/"}>Activities</.a>
      /
      #<%= @activity.activity_id %>
    </div>

    <h1 class="title"><%= @activity.title %></h1>
    <p><%= @activity.description %></p>
    <div class="mb-p">
      <h3 class="subheading">
        →
        <.a
          target="_blank"
          href={"https://southfrasersar.team-manager.ca.d4h.com/team/exercises/view/#{@activity.activity_id}"}
        >
          Open in D4H
        </.a>
      </h3>
      <h3 class="subheading">
        →
        <.a navigate={~p"/southfrasersar/activities/#{@activity.activity_id}/attendance"}>
          Attendance
        </.a>
      </h3>
      <!--
      <h3 class="subheading">
        →
        <.a navigate={~p"/southfrasersar/activities/#{@activity.activity_id}/mileage"}>
          Mileage Report
        </.a>
      </h3>
      -->
    </div>
    """
  end
end

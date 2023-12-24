defmodule Web.ActivityLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Adapter.Mapbox
  alias App.Model.Activity

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    activity = Activity.get(params["id"])

    mapbox = Mapbox.build_context()
    map_image_url = Mapbox.build_static_map_url(mapbox, activity.coordinate)

    socket =
      assign(socket,
        page_title: activity.title,
        activity: activity,
        map_image_url: map_image_url
      )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="mb-p05 text-sm">
      <.a navigate={~p"/#{@current_team.subdomain}"}><%= @current_team.name %></.a>
      /
      <.a navigate={~p"/#{@current_team.subdomain}/activities/"}>Activities</.a>
      /
      #<%= @activity.ref_id %>
    </div>

    <h1 class="title"><%= @activity.title %></h1>
    <p>
      <.activity_kind_badge activity={@activity} />
      <.activity_tracking_number_badge activity={@activity} />
    </p>

    <div><%= @activity.description %></div>
    <.activity_tags activity={@activity} class="mb-p" />

    <div class="mb-p">
      <h3 class="subheading">
        → <.a
          external={true}
          external_icon_class="w-6 h-6"
          href={D4H.build_activity_url(@current_team, @activity)}
          phx-no-format
        >Open D4H Activity</.a>
      </h3>
      <h3 class="subheading">
        →
        <.a navigate={~p"/#{@current_team.subdomain}/activities/#{@activity.id}/attendance"}>
          Attendance
        </.a>
      </h3>
      <h3 class="subheading">
        →
        <.a navigate={~p"/#{@current_team.subdomain}/activities/#{@activity.id}/mileage"}>
          Mileage Report
        </.a>
      </h3>
    </div>
    <p :if={false && @map_image_url}>
      <img src={@map_image_url} width="640" height="480" alt="Map of activity" />
    </p>
    """
  end
end

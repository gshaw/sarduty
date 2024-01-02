defmodule Web.ActivityLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Adapter.Mapbox
  alias App.Model.Activity
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    activity = Activity.get(params["id"])
    members = fetch_members(activity)

    mapbox = Mapbox.build_context()
    map_image_url = Mapbox.build_static_map_url(mapbox, activity.coordinate)

    socket =
      assign(socket,
        page_title: activity.title,
        activity: activity,
        members: members,
        map_image_url: map_image_url
      )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Activities" path={~p"/#{@current_team.subdomain}/activities/"} />
      <:item label={"##{@activity.ref_id}"} />
    </.breadcrumbs>

    <h1 class="title"><%= @activity.title %></h1>
    <p><.activity_badges activity={@activity} /></p>
    <p><%= Service.Format.short_date(@activity.started_at) %></p>
    <p><%= @activity.address %> · <%= @activity.coordinate %></p>

    <pre><%= @activity.description %></pre>
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
          Import Attendance
        </.a>
      </h3>
      <h3 class="subheading">
        →
        <.a navigate={~p"/#{@current_team.subdomain}/activities/#{@activity.id}/mileage"}>
          Mileage Report
        </.a>
      </h3>
    </div>

    <div class="my-p">
      <h2 class="heading">Attendance</h2>
      <.table id="member_collection" rows={@members}>
        <:col :let={record} label="ID" class="w-px" align="right">
          <%= record.ref_id %>
        </:col>
        <:col :let={record} label="Name">
          <.a navigate={~p"/#{@current_team.subdomain}/members/#{record.id}"}>
            <%= record.name %>
          </.a>
        </:col>
        <:col :let={record} label="Role" class="">
          <%= record.position %>
        </:col>
      </.table>
    </div>

    <p :if={false && @map_image_url}>
      <img src={@map_image_url} width="640" height="480" alt="Map of activity" />
    </p>
    """
  end

  def fetch_members(activity) do
    activity
    |> Ecto.assoc(:members)
    |> order_by(:name)
    |> Repo.all()
  end
end

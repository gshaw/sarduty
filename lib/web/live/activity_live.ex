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
    <table class="table table-form">
      <tbody>
        <tr>
          <th>Kind</th>
          <td><.activity_badges activity={@activity} /></td>
        </tr>
        <tr>
          <th>Date</th>
          <td><%= Service.Format.short_date(@activity.started_at) %></td>
        </tr>
        <tr :if={@activity.address}>
          <th>Address</th>
          <td><%= @activity.address %></td>
        </tr>
        <tr :if={@activity.coordinate}>
          <th>Coordinate</th>
          <td><%= @activity.coordinate %></td>
        </tr>
        <tr>
          <th>Actions</th>
          <td>
            <ul class="action-list">
              <li>
                <.a
                  external={true}
                  external_icon_class="w-6 h-6"
                  href={D4H.build_activity_url(@current_team, @activity)}
                  phx-no-format
                >Open D4H Activity</.a>
              </li>
              <li>
                <.a navigate={~p"/#{@current_team.subdomain}/activities/#{@activity.id}/attendance"}>
                  Import Attendance
                </.a>
              </li>
              <li>
                <.a navigate={~p"/#{@current_team.subdomain}/activities/#{@activity.id}/mileage"}>
                  Mileage Report
                </.a>
              </li>
            </ul>
          </td>
        </tr>
        <tr>
          <th>Description</th>
          <td><.markdown content={@activity.description} /></td>
        </tr>
        <tr>
          <th>Tags</th>
          <td><.activity_tags activity={@activity} /></td>
        </tr>
      </tbody>
    </table>

    <div class="my-p">
      <h3 class="table-heading">Attendance</h3>
      <.table id="member_collection" rows={@members} class="table-striped">
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
      <p class="my-1"><%= Enum.count(@members) %> members</p>
    </div>

    <div :if={false && @map_image_url} class="my-p">
      <h3 class="table-heading">Map</h3>
      <img src={@map_image_url} width="640" height="480" alt="Map of activity" />
    </div>
    """
  end

  def fetch_members(activity) do
    activity
    |> Ecto.assoc(:members)
    |> order_by(:name)
    |> Repo.all()
  end
end

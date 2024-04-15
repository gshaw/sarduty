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
    activity = fetch_activity(params["id"])
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
      <:item label="Activities" path={~p"/#{@current_team.subdomain}/activities"} />
      <:item label={"##{@activity.ref_id}"} />
    </.breadcrumbs>

    <h1 class="title"><%= @activity.title %></h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content activity={@activity} />
      </aside>
      <main class="content-2/3">
        <.main_content activity={@activity} map_image_url={@map_image_url} members={@members} />
      </main>
    </div>
    """
  end

  def sidebar_content(assigns) do
    ~H"""
    <dl>
      <dt>Kind</dt>
      <dd><.activity_badges activity={@activity} /></dd>

      <dt>Date</dt>
      <dd>
        <%= Service.Format.medium_datetime(@activity.started_at, @activity.team.timezone) %>
      </dd>
      <dt>Duration</dt>
      <dd>
        <%= Service.Format.long_duration(@activity.started_at, @activity.finished_at) %>
      </dd>

      <dt>Actions</dt>
      <dd>
        <ul class="action-list">
          <li>
            <.a external={true} href={D4H.activity_url(@activity.team, @activity)}>
              Open D4H Activity
            </.a>
          </li>
          <li>
            <.a navigate={~p"/#{@activity.team.subdomain}/activities/#{@activity.id}/attendance"}>
              Import Attendance
            </.a>
          </li>
          <li>
            <.a navigate={~p"/#{@activity.team.subdomain}/activities/#{@activity.id}/mileage"}>
              Mileage Report
            </.a>
          </li>
        </ul>
      </dd>
    </dl>
    """
  end

  def main_content(assigns) do
    ~H"""
    <dl>
      <p :if={@map_image_url}>
        <img src={@map_image_url} width="640" height="480" alt="Map of activity" />
      </p>
      <div :if={@activity.address || @activity.coordinate}>
        <dt>Address</dt>
        <dd><%= @activity.address %></dd>
        <dt>Coordinate</dt>
        <dd>
          <%= @activity.coordinate %>
        </dd>
      </div>

      <dt>Description</dt>
      <dd class="no-section-divider"><.markdown content={@activity.description} /></dd>

      <dt>Tags</dt>
      <dd><.activity_tags activity={@activity} /></dd>

      <dt>
        Attendance
        <span class="hint">
          · <%= Enum.count(@members) %> members
        </span>
      </dt>
      <dd>
        <.table id="member_collection" rows={@members} class="mt-p05 table-striped w-fit">
          <:col :let={record} label="ID" class="w-px" align="right">
            <%= record.ref_id %>
          </:col>
          <:col :let={record} label="Name">
            <.a navigate={~p"/#{@activity.team.subdomain}/members/#{record.id}"}>
              <%= record.name %>
            </.a>
          </:col>
          <:col :let={record} label="Role">
            <%= record.position %>
          </:col>
        </.table>
      </dd>
    </dl>
    """
  end

  def fetch_activity(activity_id) do
    activity_id
    |> Activity.get()
    |> Repo.preload(:team)
  end

  def fetch_members(activity) do
    activity
    |> Ecto.assoc(:members)
    |> order_by(:name)
    |> Repo.all()
  end
end

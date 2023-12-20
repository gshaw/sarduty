defmodule Web.ActivityCollectionLive do
  use Web, :live_view_app

  alias App.Model.Activity

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    date_filter = valid_date_filter(params)

    activities =
      Activity.get_by(team_id: socket.assigns.current_team.id, date_filter: date_filter)

    socket =
      assign(
        socket,
        page_title: "Activities",
        activities: activities,
        date_filter: date_filter
      )

    {:noreply, socket}
  end

  defp valid_date_filter(%{"date" => date_filter})
       when date_filter in ~w(all future past) do
    String.to_existing_atom(date_filter)
  end

  defp valid_date_filter(_params), do: :past

  def render(assigns) do
    ~H"""
    <div class="mb-p05 text-sm">
      <.a navigate={~p"/#{@current_team.subdomain}"}><%= @current_team.name %></.a>
    </div>
    <h1 class="title mb-p"><%= @page_title %></h1>
    <div class="mb-p">
      <.a
        navigate={~p"/#{@current_team.subdomain}/activities?date=past"}
        disabled={@date_filter == :past}
        class="btn"
      >
        Past
      </.a>
      <.a
        navigate={~p"/#{@current_team.subdomain}/activities?date=future"}
        disabled={@date_filter == :future}
        class="btn"
      >
        Future
      </.a>
      <.a
        navigate={~p"/#{@current_team.subdomain}/activities?date=all"}
        disabled={@date_filter == :all}
        class="btn"
      >
        All
      </.a>
    </div>

    <.table id="activity_collection" rows={@activities}>
      <:col :let={record} label="Activity">
        <.a navigate={~p"/#{@current_team.subdomain}/activities/#{record.id}"}>
          <.activity_title activity={record} /> #<%= record.ref_id %>
          <%= record.title %>
        </.a>
        <div class="hint break-words">
          <%= Service.StringHelpers.truncate(record.description, max_length: 120) %>
        </div>
        <.activity_tags activity={record} />
      </:col>
      <:col :let={record} label="Kind">
        <.activity_kind_badge activity={record} />
        <.activity_tracking_number_badge activity={record} />
      </:col>
      <:col :let={record} label="Date">
        <span class="whitespace-nowrap">
          <%= Calendar.strftime(record.started_at, "%x") %>
        </span>
      </:col>
    </.table>
    """
  end
end

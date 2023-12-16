defmodule Web.ActivityCollectionLive do
  use Web, :live_view_app

  alias App.Adapter.D4H
  import Web.WebComponents.A

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    filter = valid_filter(params)

    d4h = D4H.build_context(socket.assigns.current_user)
    activities = D4H.fetch_activites(d4h, params: build_params(filter))

    socket =
      assign(
        socket,
        page_title: "Activities",
        activities: activities,
        filter: filter
      )

    {:noreply, socket}
  end

  defp valid_filter(%{"filter" => filter}) when filter in ~w(all future past) do
    String.to_existing_atom(filter)
  end

  defp valid_filter(_params), do: :past

  defp build_params(:past), do: [limit: 100, sort: "date:desc", before: "now"]
  defp build_params(:future), do: [limit: 100, sort: "date:asc", after: "now"]
  defp build_params(:all), do: [sort: "date:desc"]

  def render(assigns) do
    ~H"""
    <div class="mb-p05 text-sm">
      <.a navigate={~p"/#{@current_team.subdomain}"}><%= @current_team.name %></.a>
    </div>
    <h1 class="title mb-p"><%= @page_title %></h1>
    <div class="mb-p">
      <.a
        navigate={~p"/#{@current_team.subdomain}/activities?filter=past"}
        disabled={@filter == :past}
        class="btn"
      >
        Past
      </.a>
      <.a
        navigate={~p"/#{@current_team.subdomain}/activities?filter=future"}
        disabled={@filter == :future}
        class="btn"
      >
        Future
      </.a>
      <.a
        navigate={~p"/#{@current_team.subdomain}/activities?filter=all"}
        disabled={@filter == :all}
        class="btn"
      >
        All
      </.a>
    </div>

    <.table id="activity_collection" rows={@activities}>
      <:col :let={record} label="Date">
        <span class="whitespace-nowrap">
          <%= Calendar.strftime(record.started_at, "%x") %>
        </span>
      </:col>
      <:col :let={record} label="Activity">
        <.a navigate={~p"/#{@current_team.subdomain}/activities/#{record.activity_id}"}>
          <%= record.title %>
        </.a>
        <div class="hint">
          <%= Service.StringHelpers.truncate(record.description, max_length: 120) %>
        </div>
      </:col>
    </.table>
    """
  end
end

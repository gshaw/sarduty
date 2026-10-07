defmodule Web.ActivityHistoryLive do
  use Web, :live_view_app_layout

  import Web.Components.ChangeHistory

  alias App.Model.Activity
  alias App.Repo
  alias App.ViewData.ChangeHistory

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    activity = team |> Activity.find!(params["id"]) |> Repo.preload(:team)

    socket =
      assign(socket,
        page_title: "#{activity.title} · History",
        activity: activity,
        entries: ChangeHistory.for_activity(team, activity)
      )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        label={"#{@activity.ref_id}"}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label="History" />
    </.breadcrumbs>

    <h1 class="title">{@activity.title}</h1>
    <.change_history id="activity-history" entries={@entries} timezone={@current_team.timezone} />
    """
  end
end

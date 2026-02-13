defmodule Web.AdminDashboardLive do
  use Web, :live_view_app_layout

  alias App.Model.Team
  alias App.Worker.RefreshTeamDataWorker
  alias App.Worker.ScheduleTeamRefreshesWorker

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")

    teams = Team.get_all()

    socket =
      socket
      |> assign(page_title: "Admin")
      |> assign(teams: teams)

    {:ok, socket}
  end

  def handle_info({:team_refreshed, updated_team}, socket) do
    teams =
      Enum.map(socket.assigns.teams, fn team ->
        if team.id == updated_team.id, do: updated_team, else: team
      end)

    {:noreply, assign(socket, teams: teams)}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title mb-p">Admin</h1>
    <div class="mb-p">
      <.button type="button" class="btn-warning" phx-click="refresh-all">
        Refresh All Teams
      </.button>
    </div>
    <.table id="teams" rows={@teams}>
      <:col :let={team} label="ID">
        {team.id}
      </:col>
      <:col :let={team} label="Name">
        {team.name}
        <.hint>
          {team.subdomain}
        </.hint>
      </:col>
      <:col :let={team} label="Last Refreshed">
        {format_refreshed_at(team)}
      </:col>
      <:col :let={team} label="Status">
        <div class={refresh_result_class(team.d4h_refresh_result)}>
          <%= if refreshing?(team.d4h_refresh_result) do %>
            <div class="flex items-center gap-2">
              <span class="inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent">
              </span>
              <span>{team.d4h_refresh_result}</span>
            </div>
          <% else %>
            <span>{team.d4h_refresh_result || "-"}</span>
          <% end %>
        </div>
      </:col>
      <:col :let={team} label="PAT?">
        {if team.d4h_access_key, do: "Yes", else: "No"}
      </:col>
      <:col :let={team} label="">
        <.button
          type="button"
          phx-click="refresh"
          phx-value-team-id={team.id}
          disabled={refreshing?(team.d4h_refresh_result)}
        >
          Refresh
        </.button>
      </:col>
    </.table>
    """
  end

  def handle_event("refresh-all", _params, socket) do
    %{}
    |> ScheduleTeamRefreshesWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "All team refreshes have been scheduled.")}
  end

  def handle_event("refresh", %{"team-id" => team_id}, socket) do
    %{team_id: String.to_integer(team_id)}
    |> RefreshTeamDataWorker.new()
    |> Oban.insert()

    {:noreply, socket}
  end

  defp format_refreshed_at(team) do
    if team.d4h_refreshed_at do
      Service.Format.short_datetime(team.d4h_refreshed_at, team.timezone)
    end
  end

  defp refresh_result_class("OK"), do: "text-success-1"
  defp refresh_result_class(nil), do: ""

  defp refresh_result_class(result) when is_binary(result) do
    if refreshing?(result) do
      "text-blue-600"
    else
      "text-danger-1"
    end
  end

  @refresh_stages [
    "Starting",
    "Team logo",
    "Members",
    "Tags",
    "Exercises",
    "Events",
    "Incidents",
    "Attendances",
    "Qualifications",
    "Qualification Awards"
  ]

  defp refreshing?(nil), do: false
  defp refreshing?("Refreshing"), do: true

  defp refreshing?(result) when is_binary(result) do
    String.contains?(result, "[") or Enum.any?(@refresh_stages, &String.contains?(result, &1))
  end
end

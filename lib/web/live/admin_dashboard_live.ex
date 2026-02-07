defmodule Web.AdminDashboardLive do
  use Web, :live_view_app_layout

  alias App.Model.Team
  alias App.Worker.RefreshTeamDataWorker

  def mount(_params, _session, socket) do
    teams = Team.get_all()

    socket =
      socket
      |> assign(page_title: "Admin")
      |> assign(teams: teams)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title mb-p">Admin</h1>
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
        <span class={refresh_result_class(team.d4h_refresh_result)}>
          {team.d4h_refresh_result}
        </span>
      </:col>
      <:col :let={team} label="PAT?">
        {if team.d4h_access_key, do: "Yes", else: "No"}
      </:col>
      <:col :let={team} label="">
        <.button type="button" phx-click="refresh" phx-value-team-id={team.id}>
          Refresh
        </.button>
      </:col>
    </.table>
    """
  end

  def handle_event("refresh", %{"team-id" => team_id}, socket) do
    %{team_id: String.to_integer(team_id)}
    |> RefreshTeamDataWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "D4H data refresh has been scheduled.")}
  end

  defp format_refreshed_at(team) do
    if team.d4h_refreshed_at do
      Service.Format.short_datetime(team.d4h_refreshed_at, team.timezone)
    end
  end

  defp refresh_result_class("OK"), do: "text-success-1"
  defp refresh_result_class(nil), do: ""
  defp refresh_result_class(_error), do: "text-danger-1"
end

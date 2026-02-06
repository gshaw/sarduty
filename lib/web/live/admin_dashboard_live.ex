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
    <h1 class="title-hero mb-p">Admin</h1>
    <table>
      <thead>
        <tr>
          <th>Name</th>
          <th>Subdomain</th>
          <th>Last Refreshed</th>
          <th>Refresh Result</th>
          <th>Has PAT?</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={team <- @teams}>
          <td>{team.name}</td>
          <td>{team.subdomain}</td>
          <td>{format_refreshed_at(team)}</td>
          <td>
            <span class={refresh_result_class(team.d4h_refresh_result)}>
              {team.d4h_refresh_result}
            </span>
          </td>
          <td>{if team.d4h_access_key, do: "Yes", else: "No"}</td>
          <td>
            <.button type="button" phx-click="refresh" phx-value-team-id={team.id}>
              Refresh
            </.button>
          </td>
        </tr>
      </tbody>
    </table>
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

  defp refresh_result_class("ok"), do: "text-success-1"
  defp refresh_result_class(nil), do: ""
  defp refresh_result_class(_error), do: "text-danger-1"
end

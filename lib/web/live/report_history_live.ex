defmodule Web.ReportHistoryLive do
  @moduledoc """
  A team's own report's History (#834): every save, newest first, with who saved it,
  whether it came from an agent's draft, and What changed. Restore opens Change report
  with that version's name, description, and query; saving it adds a new version, so
  nothing is rewritten. Picked values were never kept in versions, so the report's
  current ones stay.
  """
  use Web, :live_view_app_layout

  alias App.Model.Member
  alias App.Model.ReportVersion
  alias App.ViewData.Reports
  alias Service.Format

  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()

    report =
      case Reports.find(team, id, now) do
        %{saved: %{} = saved} -> saved
        _built_in_or_none -> raise Web.Status.NotFound
      end

    versions =
      report
      |> ReportVersion.get_all()
      |> Enum.map(&%{version: &1, by: Member.name_for_user(team, &1.user, now)})

    {:ok,
     assign(socket,
       page_title: "History · #{report.name}",
       report: report,
       versions: versions,
       latest_id: versions |> List.first() |> then(& &1.version.id)
     )}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Reports" path={~p"/teams/#{@current_team}/reports"} />
      <:item label={@report.name} path={~p"/teams/#{@current_team}/reports/#{@report.id}"} />
      <:item label="History" />
    </.breadcrumbs>
    <h1 class="title">History</h1>
    <p class="lead">
      Every save of {@report.name}, newest first. Restore opens the report with that version, and saving it adds a new one.
    </p>

    <.table id="report-versions" rows={@versions} row_id={&"version-#{&1.version.id}"}>
      <:col :let={row} label="Saved" class="w-px whitespace-nowrap">
        {Format.datetime_short(row.version.inserted_at, @current_team.timezone)}
      </:col>
      <:col :let={row} label="By" class="whitespace-nowrap">
        {row.by || "A team admin"}{from_draft(row.version.agent)}
      </:col>
      <:col :let={row} label="What changed">
        {row.version.change}
      </:col>
      <:col :let={row} label="" class="w-px">
        <.button
          :if={row.version.id != @latest_id}
          id={"version-restore-#{row.version.id}"}
          size={:sm}
          navigate={
            ~p"/teams/#{@current_team}/reports/#{@report.id}/edit?#{[version: row.version.id]}"
          }
        >
          Restore
        </.button>
      </:col>
    </.table>
    """
  end

  defp from_draft(nil), do: nil
  defp from_draft(agent), do: ", from #{Reports.possessive(agent)} draft"
end

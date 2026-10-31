defmodule Web.ReportCollectionLive do
  @moduledoc """
  Reports (#768): every report a team admin can run, the team's own first, then the ones
  built into SAR Duty (App.Report.BuiltIn).
  """
  use Web, :live_view_app_layout

  alias App.ViewData.Reports

  def mount(_params, _session, socket) do
    reports = Reports.list(socket.assigns.current_team, DateTime.utc_now())
    {:ok, assign(socket, page_title: "Reports", saved: reports.saved, built_in: reports.built_in)}
  end

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">{@page_title}</h1>
      <:action>
        <.button id="report-new" navigate={~p"/teams/#{@current_team}/reports/new"}>New report</.button>
      </:action>
    </.heading_row>
    <p class="lead">
      Questions about your team's records, as tables you can download. Every report runs here, on your records.
    </p>

    <section :if={@saved != []} id="saved-reports-section">
      <h2 class="heading mt-8">Your team's reports</h2>
      <.table id="saved-reports" rows={@saved} row_id={&"report-#{&1.slug}"} class="table-striped">
        <:col :let={report} label="Report">
          <.a navigate={~p"/teams/#{@current_team}/reports/#{report.slug}"}>{report.name}</.a>
          <div :if={report.about} class="hint">{report.about}</div>
        </:col>
        <:col :let={report} label="Shows" class="w-px whitespace-nowrap">{report.shows}</:col>
        <:col :let={report} label="Made by" class="whitespace-nowrap">
          {report.made_by || "A team admin"}
        </:col>
        <:col :let={report} label="Date" class="w-px whitespace-nowrap">
          <.date_cell value={report.made_on} timezone={@current_team.timezone} />
        </:col>
      </.table>
    </section>

    <h2 class="heading mt-8">Built in</h2>
    <p class="hint">Part of SAR Duty. Copy one to change it.</p>
    <.table id="built-in-reports" rows={@built_in} row_id={&"report-#{&1.slug}"} class="table-striped">
      <:col :let={report} label="Report">
        <.a navigate={~p"/teams/#{@current_team}/reports/#{report.slug}"}>{report.name}</.a>
        <div class="hint">{report.about}</div>
      </:col>
      <:col :let={report} label="Shows" class="w-px whitespace-nowrap">{report.shows}</:col>
    </.table>
    """
  end
end

defmodule Web.ReportCollectionLive do
  @moduledoc """
  Reports (#768): every report a team admin can run. The built-in ones come with SAR
  Duty; see App.Report.BuiltIn.
  """
  use Web, :live_view_app_layout

  alias App.Report.BuiltIn
  alias App.Report.Catalog
  alias App.Report.Parser

  def mount(_params, _session, socket) do
    built_in = Enum.map(BuiltIn.all(), &Map.put(&1, :shows, shows(&1.query)))
    {:ok, assign(socket, page_title: "Reports", built_in: built_in)}
  end

  # What a report lists, from the subject after its `from`.
  defp shows(query) do
    {:ok, %{from: from}} = Parser.parse(query)
    Catalog.subject(from).label
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">{@page_title}</h1>
    <p class="lead">
      Questions about your team's records, as tables you can download. Every report runs here, on your records.
    </p>

    <h2 class="heading mt-8">Built in</h2>
    <p class="hint">Part of SAR Duty.</p>

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

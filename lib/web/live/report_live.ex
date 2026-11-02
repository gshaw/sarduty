defmodule Web.ReportLive do
  @moduledoc """
  One report (#768), the team's own or built in, run on the team's records. Each `:name`
  in its query is a menu above the rows, and its page's clauses draw tiles, a search,
  filters, sortable headers, and pages (#784). Every pick rides in the URL, so two team
  admins can run it for different years; what the URL leaves out, a team's own report
  takes from the values saved with it. Download CSV gives the same rows, every page.
  Its actions are a line of links under its description (`<.page_actions>`); Delete report
  is one of them, for a team's own report.
  """
  use Web, :live_view_app_layout

  import Web.Components.ReportChart
  import Web.Components.ReportPage
  import Web.Components.ReportTable

  alias App.Adapter.D4H
  alias App.Model.SavedReport
  alias App.Operation.SaveReport
  alias App.Report
  alias App.Report.BuiltIn
  alias App.Report.Chart
  alias App.Report.Compiler
  alias App.Report.Error
  alias App.Report.Value
  alias App.ViewData.ReportRecords
  alias App.ViewData.Reports
  alias Service.Format
  alias Web.Components.ReportPage

  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(%{"id" => id} = params, _uri, socket) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()
    report = Reports.find(team, id, now) || raise Web.Status.NotFound

    socket =
      socket
      |> assign(page_title: report.name, report: report, now: now)
      |> assign(fix: BuiltIn.fix(report.id, D4H.service(team)))
      |> run(report, given(params, report), now)

    {:noreply, socket}
  end

  # The URL's picks by name, over the ones saved with the report.
  defp given(params, report), do: Map.merge(report.values, Map.drop(params, ["subdomain", "id"]))

  defp run(socket, report, given, now) do
    team = socket.assigns.current_team

    # Experiment (charts): the engine reads the query; a chart line under it draws above.
    case report.query |> Chart.query_text() |> Report.page(team, given, now) do
      {:ok, view} ->
        # A pick the report was saved with is where it starts, so a URL leaves it out.
        view = %{view | defaults: Map.merge(view.defaults, report.values)}
        values = Map.new(view.values, &{&1.name, Value.param(&1)})
        base = ~p"/teams/#{team}/reports/#{report.id}"

        assign(socket,
          view: view,
          records: ReportRecords.load(view.result, team, now),
          values: view.values,
          form: to_form(values, as: "values"),
          controls: ReportPage.controls_form(view),
          path_fn: &ReportPage.path(view, base, &1),
          csv_path: csv_path(team, report, view),
          chart: chart(report, team, given, now),
          error: nil
        )

      {:error, %Error{} = error} ->
        assign(socket, view: nil, values: [], error: Error.text(error), csv_path: nil, chart: nil)
    end
  end

  defp chart(report, team, given, now) do
    with %Chart{} = spec <- Chart.find(report.query),
         {:ok, run} <- Chart.run(%{spec | name: report.name}, team, given, now) do
      %{
        spec: %{spec | name: report.name},
        run: run,
        records: ReportRecords.load(run.result, team, now)
      }
    else
      _none -> nil
    end
  end

  defp csv_path(team, report, view) do
    params = Map.delete(view.params, "page")
    ~p"/teams/#{team}/reports/#{report.id}/csv?#{params}"
  end

  def handle_event("change", %{"values" => values}, socket) do
    path = socket.assigns.path_fn.([{:page, nil} | Map.to_list(values)])
    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  def handle_event("delete", _params, socket) do
    %{current_team: team, report: %{saved: %SavedReport{} = saved}} = socket.assigns
    SaveReport.delete(saved)

    {:noreply,
     socket
     |> put_flash(:info, "Deleted the #{saved.name} report.")
     |> push_navigate(to: ~p"/teams/#{team}/reports")}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Reports" path={~p"/teams/#{@current_team}/reports"} />
      <:item label={@report.name} />
    </.breadcrumbs>

    <h1 class="title">{@report.name}</h1>
    <p :if={@report.about} class="lead">{@report.about}</p>
    <.page_actions id="report-actions">
      <:byline :if={@report.saved}>
        Saved by {@report.made_by || "a team admin"} on {Format.date_short(
          @report.made_on,
          @current_team.timezone
        )}.
      </:byline>
      <:byline :if={!@report.saved}>Built in, part of SAR Duty.</:byline>
      <:action :if={@report.saved}>
        <.a id="report-change" navigate={~p"/teams/#{@current_team}/reports/#{@report.id}/edit"}>Change report</.a>
      </:action>
      <:action :if={!@report.saved}>
        <.a
          id="report-copy"
          navigate={~p"/teams/#{@current_team}/reports/new?#{[from: @report.id]}"}
        >Copy report</.a>
      </:action>
      <:action :if={@csv_path}>
        <.a id="report-csv" href={@csv_path}>Download CSV</.a>
      </:action>
      <:action :if={@report.saved}>
        <.a
          id="report-delete"
          href="#"
          phx-click="delete"
          phx-disable-with="Deleting…"
          {Web.DeleteConfirm.report(@report.saved)}
        >Delete report</.a>
      </:action>
    </.page_actions>
    <p :if={@fix} id="report-fix" class="hint">{@fix}</p>

    <.filter_form :if={@values != []} for={@form} id="report-values">
      <.report_value
        :for={value <- @values}
        value={value}
        id={"report-value-#{value.name}"}
        name={"values[#{value.name}]"}
      />
    </.filter_form>

    <.banner :if={@error} kind={:danger} title="This report cannot run" id="report-error">
      <p>{@error}</p>
      <p :if={@report.saved}>Change the report to fix its query.</p>
    </.banner>

    <.report_chart
      :if={@chart}
      id="report-chart"
      chart={@chart.spec}
      run={@chart.run}
      records={@chart.records}
      team={@current_team}
    />

    <div :if={@view}>
      <.report_page
        id="report"
        view={@view}
        records={@records}
        team={@current_team}
        now={@now}
        path_fn={@path_fn}
        form={@controls}
      />
      <p :if={@view.result.more?} id="report-more" class="hint">
        Shows the first {Format.number(Compiler.max_rows())} rows.
      </p>
      <.empty_state :if={@view.result.rows == []} id="report-empty" title="Nothing to show">
        {if @values == [] and @view.filters == [] and !@view.search?,
          do: "Nothing matches the report yet.",
          else: "Pick other values above."}
      </.empty_state>
    </div>
    """
  end
end

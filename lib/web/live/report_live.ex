defmodule Web.ReportLive do
  @moduledoc """
  One report (#768), the team's own or built in, run on the team's records. Each `:name`
  in its query is a menu above the rows, and its page's clauses draw tiles, a search,
  filters, sortable headers, and pages (#784). Every pick rides in the URL, so two team
  admins can run it for different years; what the URL leaves out, a team's own report
  takes from the values saved with it. Download CSV gives the same rows, every page.
  """
  use Web, :live_view_app_layout

  import Web.Components.ReportPage
  import Web.Components.ReportTable

  alias App.Adapter.D4H
  alias App.Report
  alias App.Report.BuiltIn
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

    case Report.page(report.query, team, given, now) do
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
          error: nil
        )

      {:error, %Error{} = error} ->
        assign(socket, view: nil, values: [], error: Error.text(error), csv_path: nil)
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

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Reports" path={~p"/teams/#{@current_team}/reports"} />
      <:item label={@report.name} />
    </.breadcrumbs>

    <.heading_row>
      <h1 class="title">{@report.name}</h1>
      <:action>
        <.button
          :if={@report.saved}
          id="report-change"
          navigate={~p"/teams/#{@current_team}/reports/#{@report.id}/edit"}
        >
          Change report
        </.button>
        <.button
          :if={!@report.saved}
          id="report-copy"
          navigate={~p"/teams/#{@current_team}/reports/new?#{[from: @report.id]}"}
        >
          Copy and change
        </.button>
        <.button :if={@csv_path} id="report-csv" href={@csv_path}>Download CSV</.button>
      </:action>
    </.heading_row>
    <p :if={@report.about} class="lead">{@report.about}</p>
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

    <details id="report-query" class="mt-8">
      <summary class="heading">Query</summary>
      <p :if={!@report.saved} class="hint">Built in, part of SAR Duty. Copy it to make your own.</p>
      <p :if={@report.saved} class="hint">
        Made by {@report.made_by || "a team admin"} on {Format.date_short(
          @report.made_on,
          @current_team.timezone
        )}.
      </p>
      <pre class="code-block"><code>{@report.query}</code></pre>
    </details>
    """
  end
end

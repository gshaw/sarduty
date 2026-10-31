defmodule Web.ReportLive do
  @moduledoc """
  One report (#768), the team's own or built in, run on the team's records. Each `:name`
  in its query is a menu above the rows, and the picked values ride in the URL, so two
  team admins can run it for different years; without them, a team's own report runs
  with the values saved with it. Download CSV gives the same rows.
  """
  use Web, :live_view_app_layout

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

  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()
    report = Reports.find(team, slug, now) || raise Web.Status.NotFound

    socket =
      socket
      |> assign(page_title: report.name, report: report, now: now)
      |> assign(fix: BuiltIn.fix(slug, D4H.service(team)))
      |> run(report, given(params, report), now)

    {:noreply, socket}
  end

  # The URL's picked values by name, or the ones saved with the report.
  defp given(params, report) do
    case Map.drop(params, ["subdomain", "slug"]) do
      empty when empty == %{} -> report.values
      values -> values
    end
  end

  defp run(socket, report, given, now) do
    team = socket.assigns.current_team

    case Report.run(report.query, team, given, now) do
      {:ok, result} ->
        values = Map.new(result.values, &{&1.name, Value.param(&1)})

        assign(socket,
          result: result,
          records: ReportRecords.load(result, team, now),
          values: result.values,
          form: to_form(values, as: "values"),
          csv_path: ~p"/teams/#{team}/reports/#{report.slug}/csv?#{values}",
          error: nil
        )

      {:error, %Error{} = error} ->
        assign(socket, result: nil, values: [], error: Error.text(error), csv_path: nil)
    end
  end

  def handle_event("change", %{"values" => values}, socket) do
    team = socket.assigns.current_team
    path = ~p"/teams/#{team}/reports/#{socket.assigns.report.slug}?#{values}"
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
          navigate={~p"/teams/#{@current_team}/reports/#{@report.slug}/edit"}
        >
          Change report
        </.button>
        <.button
          :if={!@report.saved}
          id="report-copy"
          navigate={~p"/teams/#{@current_team}/reports/new?#{[from: @report.slug]}"}
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

    <div :if={@result}>
      <p id="report-count" class="hint">{count(@result)}</p>
      <.report_table
        :if={@result.rows != []}
        id="report-rows"
        result={@result}
        records={@records}
        team={@current_team}
        now={@now}
      />
      <p :if={@result.more?} id="report-more" class="hint">
        Shows the first {Format.number(Compiler.max_rows())} rows.
      </p>
      <.empty_state :if={@result.rows == []} id="report-empty" title="Nothing to show">
        {if @values == [], do: "Nothing matches the report yet.", else: "Pick other values above."}
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

  @doc ~s(How many rows: "7 members" when the first column is a record, "12 rows" otherwise.)
  def count(result) do
    n = length(result.rows)

    case result.columns do
      [%{type: {:record, kind}} | _] ->
        Format.count(n, one: "%d #{kind_name(kind)}", many: "%d #{kind_names(kind)}")

      _other ->
        Format.count(n, one: "%d row", many: "%d rows")
    end
  end

  defp kind_name(kind), do: Atom.to_string(kind)

  defp kind_names(:activity), do: "activities"
  defp kind_names(kind), do: kind_name(kind) <> "s"
end

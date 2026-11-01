defmodule Web.ReportLive do
  @moduledoc """
  One report (#768), run on the team's records. Each `:name` in its query is a menu
  above the rows, and the picked values ride in the URL, so two team admins can run it
  for different years. Download CSV gives the same rows.
  """
  use Web, :live_view_app_layout

  import Web.Components.ReportTable

  alias App.Adapter.D4H
  alias App.Report
  alias App.Report.BuiltIn
  alias App.Report.Error
  alias App.Report.Value
  alias App.ViewData.ReportRecords
  alias Service.Format

  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    report = BuiltIn.get(slug) || raise Web.Status.NotFound
    team = socket.assigns.current_team
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(page_title: report.name, report: report, now: now)
      |> assign(fix: BuiltIn.fix(slug, D4H.service(team)))
      |> run(report, given(params), now)

    {:noreply, socket}
  end

  # The URL's picked values, by name.
  defp given(params), do: Map.drop(params, ["subdomain", "slug"])

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
    path =
      ~p"/teams/#{socket.assigns.current_team}/reports/#{socket.assigns.report.slug}?#{values}"

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
        <.button :if={@csv_path} id="report-csv" href={@csv_path}>Download CSV</.button>
      </:action>
    </.heading_row>
    <p class="lead">{@report.about}</p>
    <p :if={@fix} id="report-fix" class="hint">{@fix}</p>

    <.filter_form :if={@values != []} for={@form} id="report-values">
      <.value_input :for={value <- @values} value={value} form={@form} />
    </.filter_form>

    <.banner :if={@error} kind={:danger} title="This report cannot run" id="report-error">
      <p>{@error}</p>
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
        Shows the first {Format.number(App.Report.Compiler.max_rows())} rows.
      </p>
      <.empty_state :if={@result.rows == []} id="report-empty" title="Nothing to show">
        {if @values == [], do: "Nothing matches the report yet.", else: "Pick other values above."}
      </.empty_state>
    </div>

    <details id="report-query" class="mt-8">
      <summary class="heading">Query</summary>
      <p class="hint">Built in, part of SAR Duty.</p>
      <pre class="code-block"><code>{@report.query}</code></pre>
    </details>
    """
  end

  attr :value, Value, required: true
  attr :form, :any, required: true

  # A menu for a year or a choice, a date box for a date, and a text box for the rest.
  defp value_input(%{value: %Value{kind: kind}} = assigns) when kind in [:year, :choice] do
    ~H"""
    <.input
      type={if length(@value.choices) > 12, do: "combobox", else: "select"}
      field={@form[@value.name]}
      label={@value.label}
      options={@value.choices}
    />
    """
  end

  defp value_input(%{value: %Value{kind: :date}} = assigns),
    do: ~H"""
    <.input type="date" field={@form[@value.name]} label={@value.label} />
    """

  defp value_input(assigns),
    do: ~H"""
    <.input type="text" field={@form[@value.name]} label={@value.label} phx-debounce="400" />
    """

  # "7 members" when the first column is a record, "12 rows" otherwise.
  defp count(result) do
    n = length(result.rows)

    case result.columns do
      [%{type: {:record, kind}} | _] ->
        Format.count(n, one: "%d #{kind_name(kind)}", many: "%d #{kind_names(kind)}")

      _other ->
        Format.count(n, one: "%d row", many: "%d rows")
    end
  end

  defp kind_name(:item), do: "item"
  defp kind_name(kind), do: Atom.to_string(kind)

  defp kind_names(:activity), do: "activities"
  defp kind_names(kind), do: kind_name(kind) <> "s"
end

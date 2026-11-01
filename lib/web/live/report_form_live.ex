defmodule Web.ReportFormLive do
  @moduledoc """
  New report and Change report (#768). The query first, its rows as you type, then the
  name: a report is named once it's right. The preview draws the page's clauses too
  (#784): its tiles, filters, and headers pick as they will on the report's page. Save
  keeps the query and the picked values, never the rows. Beside the query, the page's
  clauses and the fields of the subject after `from`; a click puts a field in the query
  where the cursor is. `?from=<id>` starts from a copy of another report, such as a
  built-in one. `?list=<slug>` is Save as report on a list such as Activities (#784): the
  list's text, with the list's picks as the values and in the name.
  """
  use Web, :live_view_app_layout

  import Web.Components.ReportPage
  import Web.Components.ReportTable

  alias App.Model.SavedReport
  alias App.Operation.SaveReport
  alias App.Report
  alias App.Report.Catalog
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Expr
  alias App.Report.Lists
  alias App.Report.Parser
  alias App.Report.View
  alias App.ViewData.ReportRecords
  alias App.ViewData.Reports
  alias Service.Format
  alias Web.Components.ReportPage

  @preview_rows 50

  @first_query """
  select name, standing, last_attended
  from members
  where counted = true
  order by name
  """

  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()
    {saved, start} = start(socket.assigns.live_action, params, team, now)

    socket
    |> assign(
      page_title: if(saved, do: "Change report", else: "New report"),
      saved: saved,
      now: now,
      context: Context.new(team, now),
      subject: Catalog.subject("members"),
      params: start
    )
    |> assign_form(SavedReport.changeset(saved || %SavedReport{}, start))
    |> preview(start)
    |> then(&{:ok, &1})
  end

  defp start(:edit, %{"id" => id}, team, now) do
    case Reports.find(team, id, now) do
      %{saved: %SavedReport{} = saved} -> {saved, %{}}
      _built_in_or_none -> raise Web.Status.NotFound
    end
  end

  defp start(:new, %{"from" => id}, team, now) do
    report = Reports.find(team, id, now) || raise Web.Status.NotFound

    {nil,
     %{
       "name" => "#{report.name} (copy)",
       "about" => report.about,
       "query" => report.query,
       "values" => report.values
     }}
  end

  defp start(:new, %{"list" => slug} = params, team, now) do
    list = Lists.get(slug) || raise Web.Status.NotFound
    values = Map.drop(params, ["list", "subdomain", "page"])

    {nil,
     %{"name" => list_name(list, values, team, now), "query" => list.query, "values" => values}}
  end

  defp start(:new, _params, _team, _now), do: {nil, %{"query" => @first_query}}

  # Named for the picks: "Activities: Exercises, 2026, rope".
  defp list_name(list, values, team, now) do
    picks =
      case Report.page(list.query, team, values, now) do
        {:ok, view} -> pick_labels(view)
        {:error, _error} -> []
      end

    name = if picks == [], do: list.name, else: "#{list.name}: #{Enum.join(picks, ", ")}"
    String.slice(name, 0, SavedReport.max_name())
  end

  defp pick_labels(view) do
    tile =
      for %{picked: picked, tiles: tiles} <- List.wrap(view.switch),
          %{value: ^picked, label: label} <- tiles,
          picked != "all",
          do: label

    filters =
      for %{picked: picked} = filter <- view.filters,
          picked not in [nil, "all", filter.default],
          {label, ^picked} <- filter.options,
          do: label

    search = if view.q == "", do: [], else: [view.q]
    tile ++ filters ++ search
  end

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: "report"))

  # Runs the query as it stands, for the rows under it, and keeps the fields beside it on
  # the last subject that read. Typing the name or about leaves the rows as they are.
  defp preview(socket, params) do
    query = Map.get(params, "query") || socket.assigns.form[:query].value || ""
    values = Map.get(params, "values") || socket.assigns.form[:values].value || %{}
    team = socket.assigns.current_team

    if socket.assigns[:ran] == {query, values} do
      socket
    else
      socket
      |> assign(ran: {query, values}, subject: subject(query) || socket.assigns.subject)
      |> assign_preview(Report.page(query, team, values, socket.assigns.now))
    end
  end

  defp assign_preview(socket, {:ok, %View{} = view}) do
    rows = Enum.take(view.result.rows, @preview_rows)
    view = %{view | result: %{view.result | rows: rows, totals: nil}}

    assign(socket,
      view: view,
      records: ReportRecords.load(view.result, socket.assigns.current_team, socket.assigns.now),
      query_error: nil
    )
  end

  defp assign_preview(socket, {:error, %Error{} = error}),
    do: assign(socket, view: nil, query_error: Error.text(error))

  defp subject(query) do
    case Parser.parse(query) do
      {:ok, %{from: from}} -> Catalog.subject(from)
      {:error, _error} -> nil
    end
  end

  # A tile, or a header that sorts, in the preview: a pick, as a menu's change is.
  def handle_event("pick", %{"name" => name, "value" => value}, socket) do
    values = Map.put(socket.assigns.form[:values].value || %{}, name, value)

    handle_event(
      "change",
      %{"report" => Map.put(socket.assigns.params, "values", values)},
      socket
    )
  end

  # The query's mistake goes on its field as you type, as Save would put it there.
  def handle_event("change", %{"report" => params}, socket) do
    socket = socket |> assign(params: params) |> preview(params)
    report = socket.assigns.saved || %SavedReport{}
    changeset = report |> SavedReport.changeset(params) |> Map.put(:action, :validate)

    changeset =
      if socket.assigns.query_error,
        do: Ecto.Changeset.add_error(changeset, :query, socket.assigns.query_error),
        else: changeset

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"report" => params}, socket) do
    %{current_team: team, current_user: user, saved: saved} = socket.assigns

    case SaveReport.call(team, user, saved, params, socket.assigns.now) do
      {:ok, report} ->
        {:noreply, push_navigate(socket, to: ~p"/teams/#{team}/reports/#{report.id}")}

      {:error, changeset} ->
        {:noreply, socket |> assign_form(changeset) |> preview(params)}
    end
  end

  def handle_event("delete", _params, socket) do
    SaveReport.delete(socket.assigns.saved)
    team = socket.assigns.current_team

    {:noreply,
     socket
     |> put_flash(:info, "Report deleted.")
     |> push_navigate(to: ~p"/teams/#{team}/reports")}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Reports" path={~p"/teams/#{@current_team}/reports"} />
      <:item
        :if={@saved}
        label={@saved.name}
        path={~p"/teams/#{@current_team}/reports/#{@saved.id}"}
      />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <div class="content-wrapper">
      <aside id="report-fields" class="content-1/3">
        <h2 class="heading">The page</h2>
        <p class="hint">Clauses after the query that draw the page around the rows.</p>
        <.table id="report-clause-table" rows={clauses()} row_id={&"clause-#{elem(&1, 0)}"}>
          <:col :let={{clause, _draws}} label="Clause"><code>{clause}</code></:col>
          <:col :let={{_clause, draws}} label="Draws">{draws}</:col>
        </.table>

        <h2 class="heading mt-8">Fields in {@subject.name}</h2>
        <p class="hint">Click a field to add it where the cursor is.</p>
        <div id="report-field-list" phx-hook="InsertField" data-target="report_query">
          <.table
            id="report-field-table"
            rows={Catalog.shown_fields(@subject, @context)}
            row_id={&"field-#{&1.name}"}
          >
            <:col :let={field} label="Field">
              <.button type="button" size={:sm} data-field={field_text(field)}>{field_text(field)}</.button>
            </:col>
            <:col :let={field} label="Holds">{field.about || field.label}</:col>
          </.table>
        </div>
        <p class="hint mt-4">
          Other subjects: {Enum.join(Catalog.names() -- [@subject.name], ", ")}.
        </p>
      </aside>

      <div class="content-2/3">
        <.form for={@form} id="report-form" phx-change="change" phx-submit="save">
          <.error_summary form={@form} />
          <.input
            field={@form[:query]}
            type="textarea"
            label="Query"
            rows="9"
            class="font-mono"
            phx-debounce="300"
            spellcheck="false"
          >
            Write :year for a value you pick each time it runs. For one member, use their ID: member.ref_id = '112'.
          </.input>

          <.report_value
            :for={value <- (@view && @view.values) || []}
            value={value}
            id={"report-form-value-#{value.name}"}
            name={"report[values][#{value.name}]"}
          />
          <input
            :for={{name, value} <- picks(@view)}
            type="hidden"
            name={"report[values][#{name}]"}
            value={value}
          />

          <div :if={@view} id="report-preview" class="mb-8">
            <.report_page
              id="report-preview"
              view={@view}
              records={@records}
              team={@current_team}
              now={@now}
              count={preview_count(@view)}
            />
          </div>

          <.input field={@form[:name]} type="text" label="Name" maxlength="80" />
          <.input field={@form[:about]} type="text" label="About" maxlength="200">
            One line under the name on Reports.
          </.input>

          <.form_actions>
            <.button id="report-save" variant={:success} phx-disable-with="Saving…">Save report</.button>
            <.button id="report-cancel" navigate={cancel_path(@current_team, @saved)}>Cancel</.button>
          </.form_actions>
        </.form>
      </div>
    </div>

    <section :if={@saved} id="report-delete" class="mt-8 measure">
      <h2 class="heading">Delete the report</h2>
      <p>Its query goes for good. The records it reads stay.</p>
      <.button
        id="report-delete-button"
        type="button"
        variant={:danger}
        phx-click="delete"
        data-confirm="Delete this report? Its query goes for good."
      >
        Delete report
      </.button>
    </section>
    """
  end

  defp field_text(field), do: Expr.example(field)

  defp cancel_path(team, nil), do: ~p"/teams/#{team}/reports"
  defp cancel_path(team, saved), do: ~p"/teams/#{team}/reports/#{saved.id}"

  defp clauses,
    do: [
      {"search", "The search box, over the fields named."},
      {"switch", "The tiles, each with its count."},
      {"filter", "A menu: All, then its options."},
      {"option", "One choice, and the where it adds."},
      {"each", "A choice per value, such as each year."},
      {"sort", "A column header that sorts."},
      {"page", "Pages of that many rows."}
    ]

  # The picks the preview's tiles and headers keep, as the form saves them.
  defp picks(nil), do: []

  defp picks(view) do
    switch = if view.switch, do: [{view.switch.name, view.switch.picked}], else: []
    sort = if view.sort, do: [{"sort", view.sort}], else: []
    switch ++ sort
  end

  defp preview_count(view) do
    count = ReportPage.count(view)

    if view.total > length(view.result.rows),
      do:
        "#{count} · shows the first #{Format.number(length(view.result.rows))} · runs as you type",
      else: "#{count} · runs as you type"
  end
end

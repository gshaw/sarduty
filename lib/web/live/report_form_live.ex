defmodule Web.ReportFormLive do
  @moduledoc """
  New report and Change report (#768). Save report at the top; the name and description
  first, then the query and its rows as you type (#784). The preview draws the page's clauses too
  (#784): its tiles, filters, and headers pick as they will on the report's page. Save
  keeps the query and the picked values, never the rows. Beside the query, the page's
  clauses and the fields of the subject after `from`; a click puts a field in the query
  where the cursor is. `?from=<id>` starts from a copy of another report, such as a
  built-in one. `?list=<slug>` is Save as report on a list such as Activities (#784): the
  list's text, with the list's picks as the values and in the name. `?query=` is an
  agent's link from check_report (#816): its query, name, and description fill the form,
  and `agent` names who wrote it, saved with the report.

  With `draft`, the page follows the agent's live draft (#834): each query the agent
  checks fills the form and reruns the rows, at most one run a second. Once the team
  admin has typed since the agent's last query, a new one waits in a toast instead of
  overwriting their typing. Nothing is saved until they save.

  Changing a saved report asks What changed, kept in its History (#834); an agent's draft
  can fill it. `?version=<id>` is Restore from History: that version's name,
  description, and query, saved as a new version.
  """
  use Web, :live_view_app_layout

  import Web.Components.ReportPage
  import Web.Components.ReportTable

  alias App.Model.ReportVersion
  alias App.Model.SavedReport
  alias App.Operation.SaveReport
  alias App.Report
  alias App.Report.Catalog
  alias App.Report.Context
  alias App.Report.Draft
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
  @draft_every_ms 1_000

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
      params: start,
      agent: agent(params)
    )
    |> assign_form(SavedReport.changeset(saved || %SavedReport{}, start))
    |> preview(start)
    |> follow(draft(params))
    |> then(&{:ok, &1})
  end

  # The agent's draft to follow, from its link: an id check_report made.
  defp draft(%{"draft" => id, "query" => _query}), do: if(Draft.id?(id), do: id)
  defp draft(_params), do: nil

  defp follow(socket, draft) do
    %{current_team: team, current_user: user} = socket.assigns
    if draft && connected?(socket), do: Draft.subscribe(team, user.id, draft)

    assign(socket,
      draft: draft,
      draft_applied: draft_fields(socket.assigns.form),
      draft_at: socket.assigns.now,
      draft_waiting: nil,
      draft_seq: 0,
      draft_next: nil,
      draft_timer: nil,
      draft_ran_ms: nil
    )
  end

  # What a draft fills, as the form holds it: the agent's last one, or the admin's typing.
  defp draft_fields(form), do: Map.new(~w(name about query)a, &{&1, form[&1].value || ""})

  defp typed_since_draft?(socket),
    do: draft_fields(socket.assigns.form) != socket.assigns.draft_applied

  defp start(:edit, %{"id" => id} = params, team, now) do
    case Reports.find(team, id, now) do
      %{saved: %SavedReport{} = saved} -> {saved, edit_start(saved, params)}
      _built_in_or_none -> raise Web.Status.NotFound
    end
  end

  defp start(:new, %{"query" => query} = params, _team, _now) when is_binary(query),
    do: {nil, params |> Map.take(["query", "name", "about"]) |> Map.put("values", %{})}

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

  # Restore from History, or an agent's link: what it changes over the saved report.
  defp edit_start(saved, %{"version" => version_id}) do
    with {id, ""} <- Integer.parse(version_id),
         %ReportVersion{} = version <- ReportVersion.get(saved, id) do
      %{"name" => version.name, "about" => version.about, "query" => version.query}
    else
      _not_found -> raise Web.Status.NotFound
    end
  end

  defp edit_start(_saved, params), do: Map.take(params, ["query", "name", "about", "change"])

  # Who wrote the query, from an agent's link: a name, cut short.
  defp agent(%{"agent" => agent, "query" => _query}) when is_binary(agent) and agent != "",
    do: String.slice(agent, 0, 80)

  defp agent(_params), do: nil

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
      for %{picked: picked, options: options} = switch <- List.wrap(view.switch),
          picked not in ["all", switch.default],
          {label, ^picked} <- options,
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
  # the last subject that read. Typing the name or description leaves the rows as they are.
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

  def handle_event("load_draft", _params, socket) do
    case socket.assigns.draft_waiting do
      nil -> {:noreply, socket}
      draft -> {:noreply, apply_draft(socket, draft)}
    end
  end

  def handle_event("stop_following", _params, socket) do
    %{current_team: team, current_user: user, draft: draft, agent: agent} = socket.assigns
    if draft, do: Draft.unsubscribe(team, user.id, draft)
    if socket.assigns.draft_timer, do: Process.cancel_timer(socket.assigns.draft_timer)

    {:noreply,
     socket
     |> assign(draft: nil, draft_waiting: nil, draft_next: nil, draft_timer: nil)
     |> put_flash(
       :info,
       "Stopped following #{Reports.possessive(agent)} draft. The form keeps what's in it."
     )}
  end

  def handle_event("save", %{"report" => params}, socket) do
    %{current_team: team, current_user: user, saved: saved} = socket.assigns

    case SaveReport.call(team, user, saved, params, socket.assigns.now, socket.assigns.agent) do
      {:ok, report} ->
        {:noreply, push_navigate(socket, to: ~p"/teams/#{team}/reports/#{report.id}")}

      {:error, changeset} ->
        {:noreply, socket |> assign_form(changeset) |> preview(params)}
    end
  end

  # A query the agent checked. It waits in a toast when the admin has typed since the
  # last one; otherwise it fills the form, at most one run a second, the latest winning.
  def handle_info({:report_draft, %Draft{} = draft}, socket) do
    saved_id = socket.assigns.saved && socket.assigns.saved.id

    cond do
      socket.assigns.draft == nil or draft.report_id != saved_id ->
        {:noreply, socket}

      typed_since_draft?(socket) ->
        {:noreply,
         assign(socket,
           agent: draft.agent,
           draft_waiting: draft,
           draft_seq: socket.assigns.draft_seq + 1
         )}

      true ->
        {:noreply, socket |> assign(agent: draft.agent, draft_next: draft) |> run_draft_soon()}
    end
  end

  def handle_info(:apply_draft, socket) do
    socket = assign(socket, draft_timer: nil)

    case socket.assigns.draft_next do
      nil ->
        {:noreply, socket}

      draft ->
        if typed_since_draft?(socket),
          do: {:noreply, assign(socket, draft_next: nil, draft_waiting: draft)},
          else: {:noreply, apply_draft(socket, draft)}
    end
  end

  defp run_draft_soon(%{assigns: %{draft_timer: timer}} = socket) when timer != nil, do: socket

  defp run_draft_soon(socket) do
    wait =
      case socket.assigns.draft_ran_ms do
        nil -> 0
        ran -> @draft_every_ms - (System.monotonic_time(:millisecond) - ran)
      end

    if wait <= 0,
      do: apply_draft(socket, socket.assigns.draft_next),
      else: assign(socket, draft_timer: Process.send_after(self(), :apply_draft, wait))
  end

  # The draft fills the form as a change would, so the rows rerun. A saved report's name
  # and description stay unless the agent sent new ones.
  defp apply_draft(socket, %Draft{} = draft) do
    sent =
      %{
        "query" => draft.query,
        "name" => draft.name,
        "about" => draft.about,
        "change" => draft.change
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    params =
      socket.assigns.params |> Map.merge(fields_params(socket.assigns.form)) |> Map.merge(sent)

    {:noreply, socket} = handle_event("change", %{"report" => params}, socket)

    assign(socket,
      draft_applied: draft_fields(socket.assigns.form),
      draft_at: draft.at,
      draft_waiting: nil,
      draft_next: nil,
      draft_ran_ms: System.monotonic_time(:millisecond)
    )
  end

  defp fields_params(form),
    do: form |> draft_fields() |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

  def render(assigns) do
    ~H"""
    <div :if={@draft_waiting} class="toasts" id="report-draft-toasts">
      <.flash
        id={"report-draft-waiting-#{@draft_seq}"}
        kind={:info}
        title={"New query from #{@draft_waiting.agent}"}
      >
        You changed the query since.
        <.a id="report-draft-load" href="#" phx-click="load_draft">Load it</.a>
      </.flash>
    </div>
    <.breadcrumbs>
      <:item label="Reports" path={~p"/teams/#{@current_team}/reports"} />
      <:item
        :if={@saved}
        label={@saved.name}
        path={~p"/teams/#{@current_team}/reports/#{@saved.id}"}
      />
      <:item label={@page_title} />
    </.breadcrumbs>
    <.heading_row>
      <h1 class="title">{@page_title}</h1>
      <:action>
        <.button id="report-save" form="report-form" variant={:success} phx-disable-with="Saving…">
          Save report
        </.button>
        <.button id="report-cancel" navigate={cancel_path(@current_team, @saved)}>Cancel</.button>
      </:action>
    </.heading_row>

    <div id="report-editor" class="content-wrapper report-editor" phx-hook="HelpToggle">
      <aside id="report-fields" class="content-1/3 report-help">
        <p class="action mb-4">
          <.a id="report-language-link" href={~p"/agents/reports"} external={true}>How to write a report</.a>
        </p>
        <h2 class="heading">The page</h2>
        <p class="hint">Clauses after the query that draw the page around the rows.</p>
        <.table id="report-clause-table" rows={clauses()} row_id={&"clause-#{elem(&1, 0)}"}>
          <:col :let={{clause, _draws}} label="Clause" class="whitespace-nowrap">
            <code>{clause}</code>
          </:col>
          <:col :let={{_clause, draws}} label="Draws">{draws}</:col>
        </.table>

        <h2 class="heading mt-8">Charts</h2>
        <p class="hint">The last line, such as chart columns. The rows decide the rest.</p>
        <.table id="report-chart-table" rows={charts()} row_id={&"chart-#{elem(&1, 0)}"}>
          <:col :let={{kind, _takes}} label="Chart" class="whitespace-nowrap">
            <code>chart {kind}</code>
          </:col>
          <:col :let={{_kind, takes}} label="Takes">{takes}</:col>
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
              <span class="hint block mt-1">{field.about || field.label}</span>
            </:col>
          </.table>
        </div>
        <p class="hint mt-4">
          Other subjects: {Enum.join(Catalog.names() -- [@subject.name], ", ")}.
        </p>
      </aside>

      <div class="content-2/3 report-main">
        <.banner
          :if={@draft}
          id="report-draft-following"
          title={"Following #{Reports.possessive(@agent)} draft"}
          class="mb-6"
        >
          <p>
            Each query it checks runs here on your records. Nothing is saved until you save.
            <.a id="report-draft-stop" href="#" phx-click="stop_following">Stop following</.a>
          </p>
        </.banner>
        <.form for={@form} id="report-form" phx-change="change" phx-submit="save">
          <.error_summary form={@form} />
          <.input field={@form[:name]} type="text" label="Name" maxlength="80" />
          <.input field={@form[:about]} type="text" label="Description" maxlength="200">
            One line under the name on Reports.
          </.input>
          <.input
            :if={@saved}
            field={@form[:change]}
            type="text"
            label="What changed (optional)"
            maxlength={SavedReport.max_change()}
          >
            One line in the report's History.
          </.input>

          <p class="action report-help-toggle">
            <.a id="report-hide-help" href="#" data-help="hide">Hide help</.a>
            <.a id="report-show-help" href="#" data-help="show">Show help</.a>
          </p>
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

          <div :if={@view} id="report-preview">
            <.report_page
              id="report-preview"
              view={@view}
              records={@records}
              team={@current_team}
              now={@now}
              maps_app={@current_user.maps_app}
              count={preview_count(@view, draft_line(assigns))}
            />
          </div>
        </.form>
      </div>
    </div>
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
      {"page", "Pages of that many rows."},
      {"chart", "A chart of the rows, the last line."}
    ]

  # What each chart takes (#826), for the help column.
  defp charts,
    do: [
      {"stat", "A number, and a line of it when the first column is a month."},
      {"columns", "A time or a name first, then counts. A pivot stacks them."},
      {"lines", "A time first, then counts. compare year adds last year."},
      {"bars", "A name first, then a count, longest first."},
      {"calendar", "date(started_at), then a count."},
      {"week", "day_of_week(started_at), hour(started_at), then a count."}
    ]

  # The picks the preview's tiles and headers keep, as the form saves them.
  defp picks(nil), do: []

  defp picks(view) do
    switch = if view.switch, do: [{view.switch.name, view.switch.picked}], else: []
    sort = if view.sort, do: [{"sort", view.sort}], else: []
    switch ++ sort
  end

  defp preview_count(view, source) do
    count = ReportPage.count(view)

    if view.total > length(view.result.rows),
      do: "#{count} · shows the first #{Format.number(length(view.result.rows))} · #{source}",
      else: "#{count} · #{source}"
  end

  # Whose query the rows are from: the agent's while the page follows it and the query
  # is still the agent's, otherwise the admin's typing.
  defp draft_line(%{draft: draft} = assigns) when draft != nil do
    if assigns.form[:query].value == assigns.draft_applied.query,
      do:
        "the agent's query from #{Format.time_short(assigns.draft_at, assigns.current_team.timezone)}",
      else: "runs as you type"
  end

  defp draft_line(_assigns), do: "runs as you type"
end

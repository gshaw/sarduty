defmodule Web.ReportFormLive do
  @moduledoc """
  New report and Change report (#768). Save report at the top; the name and description
  first, then the query and its rows as you type (#784). The preview draws the page's clauses too
  (#784): its tiles, filters, and headers pick as they will on the report's page. Save
  keeps the query and the picked values, never the rows. Under the query, the fields of
  the subject after `from` as buttons; a click puts one in the query where the cursor is.
  How to write a report has the page's clauses and what each chart takes. `?from=<id>` starts from a copy of another report, such as a
  built-in one. `?list=<slug>` is Save as report on a list such as Activities (#784): the
  list's text, with the list's picks as the values and in the name.

  AI writing (docs/ai-writing.md): when it's open to the admin, a column beside the
  report, above it under 1024px: the asks as a conversation, oldest first, in the page
  only, each with AI's note and Undo when it changed the report; then the describe box.
  The query is hidden, since AI writes it; Show query opens it. Each ask runs in
  `start_async` (App.Operation.AskAI) with the visit's earlier asks and notes, and fills
  the form as typing would, so the rows rerun here, on the team's records, after Claude
  is done. The running ask shows at once, with its step and Stop under it. Undo puts back
  the query, name, and description from before an ask and drops the asks after it. A
  failed or stopped ask is a toast, and its words go back in the box. Nothing is saved
  until Save, which notes the version came from AI. With AI writing open, What changed
  goes: AI writes the History line after the save (App.Operation.WriteHistoryLine).

  A blank New report with AI writing open starts with the box alone, then built-in
  reports to start from (BuiltIn.starters/1) and Write the query yourself. The first
  ask that changes the report, or Write the query yourself, opens the editor.

  The name is the page's title and the description the line under it (#834). Rename is a
  step of its own: their fields with Rename and Cancel, and the rest of the page hidden
  until one is chosen. A save they stop shows their fields too, with the rest. The fields
  show whenever the query does.

  Changing a saved report asks What changed, kept in its History (#834), unless AI writes
  it. `?version=<id>` is Restore from History: that version's name, description, and
  query, saved as a new version.
  """
  use Web, :live_view_app_layout

  import Web.Components.AIWriting
  import Web.Components.ReportPage
  import Web.Components.ReportTable

  alias App.AI.ReportJob
  alias App.Model.ReportVersion
  alias App.Model.SavedReport
  alias App.Operation.AskAI
  alias App.Operation.SaveReport
  alias App.Operation.WriteHistoryLine
  alias App.Report
  alias App.Report.BuiltIn
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
  @chart_icons %{columns: "chart-column", bars: "chart-bar"}

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
      renaming: false,
      rename_from: nil
    )
    |> assign_form(SavedReport.changeset(saved || %SavedReport{}, start))
    |> preview(start)
    |> assign_ai(blank_new?(socket.assigns.live_action, params))
    |> then(&{:ok, &1})
  end

  # With AI writing open, the query starts folded: AI writes it. A blank New report
  # starts from the box alone.
  defp assign_ai(socket, blank_new?) do
    %{current_team: team, current_user: user, saved: saved, now: now} = socket.assigns
    ai = AskAI.check(team, user, now)

    assign(socket,
      ai: ai,
      ai_line: WriteHistoryLine.writes?(team, user, saved, nil, now),
      ai_form: ask_form(""),
      ai_step: nil,
      ai_pending: nil,
      ai_asks: [],
      starting: blank_new? and ai == :ok,
      query_open: ai != :ok
    )
  end

  defp blank_new?(:new, params), do: not Enum.any?(~w(from list), &Map.has_key?(params, &1))
  defp blank_new?(_action, _params), do: false

  defp ask_form(ask), do: to_form(%{"ask" => ask}, as: "ai")

  defp start(:edit, %{"id" => id} = params, team, now) do
    case Reports.find(team, id, now) do
      %{saved: %SavedReport{} = saved} -> {saved, edit_start(saved, params)}
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

  # Restore from History: what it changes over the saved report.
  defp edit_start(saved, %{"version" => version_id}) do
    with {id, ""} <- Integer.parse(version_id),
         %ReportVersion{} = version <- ReportVersion.get(saved, id) do
      %{"name" => version.name, "about" => version.about, "query" => version.query}
    else
      _not_found -> raise Web.Status.NotFound
    end
  end

  defp edit_start(_saved, _params), do: %{}

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

  # Rename keeps the name and description as they were, for Cancel.
  def handle_event("rename", _params, socket) do
    form = socket.assigns.form
    from = %{"name" => form[:name].value || "", "about" => form[:about].value || ""}
    {:noreply, assign(socket, renaming: true, rename_from: from)}
  end

  def handle_event("rename_keep", _params, socket),
    do: {:noreply, assign(socket, renaming: false, rename_from: nil)}

  def handle_event("rename_cancel", _params, socket) do
    params =
      socket.assigns.params
      |> Map.merge(fields_params(socket.assigns.form))
      |> Map.merge(socket.assigns.rename_from || %{})

    {:noreply, socket} = handle_event("change", %{"report" => params}, socket)
    {:noreply, assign(socket, renaming: false, rename_from: nil)}
  end

  def handle_event("show_query", _params, socket),
    do: {:noreply, assign(socket, query_open: true)}

  def handle_event("hide_query", _params, socket),
    do: {:noreply, assign(socket, query_open: false)}

  def handle_event("write_own", _params, socket),
    do: {:noreply, assign(socket, starting: false, query_open: true)}

  def handle_event("ask", %{"ai" => %{"ask" => ask}}, socket) do
    case String.trim(ask) do
      "" -> {:noreply, socket}
      _ask when socket.assigns.ai_step != nil -> {:noreply, socket}
      ask -> {:noreply, start_ask(socket, ask)}
    end
  end

  def handle_event("cancel_ask", _params, socket) do
    pending = socket.assigns.ai_pending

    {:noreply,
     socket
     |> cancel_async(:ai_ask)
     |> assign(ai_step: nil, ai_pending: nil, ai_form: ask_form((pending && pending.ask) || ""))
     |> put_flash(:info, "Stopped. Nothing changed.")}
  end

  def handle_event("undo_ask", %{"id" => id}, socket) do
    case Enum.split_while(socket.assigns.ai_asks, &(to_string(&1.id) != id)) do
      {_newer, [ask | older]} ->
        params =
          socket.assigns.params
          |> Map.merge(fields_params(socket.assigns.form))
          |> Map.merge(ask.before)

        {:noreply, socket} = handle_event("change", %{"report" => params}, socket)

        {:noreply,
         socket
         |> assign(ai_asks: older)
         |> put_flash(:info, "Undone. The query is back to before that ask.")}

      {_all, []} ->
        {:noreply, socket}
    end
  end

  def handle_event("save", %{"report" => params}, socket) do
    %{current_team: team, current_user: user, saved: saved} = socket.assigns

    agent = ai_agent(socket.assigns.ai_asks)

    case SaveReport.call(team, user, saved, params, socket.assigns.now, agent) do
      {:ok, report} ->
        {:noreply, push_navigate(socket, to: ~p"/teams/#{team}/reports/#{report.id}")}

      {:error, changeset} ->
        renaming =
          Keyword.has_key?(changeset.errors, :name) or Keyword.has_key?(changeset.errors, :about)

        {:noreply,
         socket
         |> assign(renaming: socket.assigns.renaming or renaming, rename_from: nil)
         |> assign_form(changeset)
         |> preview(params)}
    end
  end

  # A save after an ask that changed the report is from AI's draft.
  defp ai_agent(asks), do: if(Enum.any?(asks, & &1.undo?), do: Reports.ai_agent())

  def handle_async(:ai_ask, {:ok, result}, socket) do
    socket = assign(socket, ai_step: nil)
    {:noreply, socket |> ask_done(result) |> assign(ai_pending: nil) |> refresh_ai()}
  end

  # Stop already put the words back.
  def handle_async(:ai_ask, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:ai_ask, {:exit, _reason}, socket) do
    {:noreply,
     socket |> ask_done({:error, :unreachable}) |> assign(ai_step: nil, ai_pending: nil)}
  end

  # The ask runs beside the page, with the visit's earlier asks; its steps arrive as
  # messages while it does.
  defp start_ask(socket, ask) do
    %{current_team: team, current_user: user, form: form, ai_asks: asks} = socket.assigns
    report = report_fields(form)
    earlier = asks |> Enum.reverse() |> Enum.map(&Map.take(&1, [:ask, :note]))
    now = DateTime.utc_now()
    pid = self()
    pending = %{ask: ask, before: fields_params(form)}

    socket
    |> assign(ai_step: :writing, ai_pending: pending, ai_form: ask_form(""))
    |> start_async(:ai_ask, fn ->
      job = ReportJob.build(team, report, ask, now, earlier)
      AskAI.call(team, user, job, now, on_step: &send(pid, {:ai_step, &1}))
    end)
  end

  # The query, and a new report's name and description.
  defp ask_done(socket, {:ok, %{query: query, note: note} = result}) do
    sent =
      %{"query" => query, "name" => result.name, "about" => result.about}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    params =
      socket.assigns.params |> Map.merge(fields_params(socket.assigns.form)) |> Map.merge(sent)

    {:noreply, socket} = handle_event("change", %{"report" => params}, socket)
    socket |> assign(starting: false) |> add_ask(blank_or(note, nil), true)
  end

  defp ask_done(socket, {:unchanged, note}),
    do: add_ask(socket, blank_or(note, "Nothing changed."), false)

  # A failed ask leaves no row: a toast says why, and its words go back in the box.
  defp ask_done(socket, {:error, reason}) do
    socket
    |> assign(ai_form: ask_form(socket.assigns.ai_pending.ask))
    |> put_flash(:error, ai_error_text(reason))
  end

  # The conversation, newest first. `undo?` is false for an ask that changed nothing.
  defp add_ask(socket, note, undo?) do
    pending = socket.assigns.ai_pending

    entry = %{
      id: System.unique_integer([:positive]),
      ask: pending.ask,
      before: pending.before,
      note: note,
      undo?: undo?
    }

    assign(socket, ai_asks: [entry | socket.assigns.ai_asks])
  end

  # Whether asks are left, now that this one counted.
  defp refresh_ai(socket) do
    %{current_team: team, current_user: user} = socket.assigns
    assign(socket, ai: AskAI.check(team, user, DateTime.utc_now()))
  end

  defp ai_error_text(:daily_limit),
    do:
      "Your team has used today's #{AskAI.asks_per_day()} asks. Ask again tomorrow, or change the query yourself."

  defp ai_error_text(reason) when reason in [:paused, :no_credit],
    do: "AI writing is paused until next month. You can still change the query yourself."

  defp ai_error_text(:busy), do: "AI writing is busy. Try again in a minute."
  defp ai_error_text(:refused), do: "AI writing cannot help with that. Try other words."

  defp ai_error_text({:checks, mistake}),
    do: "Its query still had a mistake: #{mistake} Ask again in other words, or fix it yourself."

  defp ai_error_text(:off), do: "AI writing is off."
  defp ai_error_text(_reason), do: "AI writing did not answer. Try again."

  # A step of the running ask: Writing, Checking it, Trying it.
  def handle_info({:ai_step, step}, socket) do
    if socket.assigns.ai_step,
      do: {:noreply, assign(socket, ai_step: step)},
      else: {:noreply, socket}
  end

  # The name, description, and query, as the form holds them.
  defp report_fields(form), do: Map.new(~w(name about query)a, &{&1, form[&1].value || ""})

  defp fields_params(form),
    do: form |> report_fields() |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

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
    <.heading_row>
      <h1 id="report-title" class="title">{title(@form, @page_title)}</h1>
      <:action>
        <.button id="report-save" form="report-form" variant={:success} phx-disable-with="Saving…">
          Save report
        </.button>
        <.button id="report-cancel" navigate={cancel_path(@current_team, @saved)}>Cancel</.button>
      </:action>
    </.heading_row>
    <p :if={!@starting and (about(@form) || !@renaming)} id="report-about" class="lead">
      {about(@form)}
      <.a :if={!@renaming} id="report-rename" href="#" phx-click="rename">Rename</.a>
    </p>

    <.ai_editor id="report-editor" ai?={ai_column?(assigns)} column_id="report-ai">
      <:column>
        <.ai_writing
          id="report-ai"
          ai={@ai}
          form={@ai_form}
          step={@ai_step}
          pending={@ai_pending}
          asks={@ai_asks}
          label="Describe a change"
          button="Change it"
          closed={ai_closed_text(@ai)}
          sees={ai_sees()}
        />
      </:column>

      <section :if={@starting} id="report-start" class="measure mb-8">
        <.ai_writing
          id="report-ai"
          ai={@ai}
          form={@ai_form}
          step={@ai_step}
          pending={@ai_pending}
          asks={@ai_asks}
          label="Describe the report you want"
          button="Write it"
          closed={ai_closed_text(@ai)}
          sees={ai_sees()}
        >
          For example: members who haven't attended in a year, or a chart of incidents by month.
        </.ai_writing>
        <h2 class="subheading mt-8">Or start from a built-in report</h2>
        <p class="hint mb-3">A click opens a copy to change. No ask is spent.</p>
        <ul id="report-start-list" class="action-list report-start-list">
          <li :for={report <- BuiltIn.starters(@current_team)} id={"report-start-#{report.slug}"}>
            <.a navigate={~p"/teams/#{@current_team}/reports/new?from=#{report.slug}"}>{report.name}</.a>
            <span :if={chart_icon(report)} class="report-start-chart">
              <.icon name={chart_icon(report)} size={:sm} />Chart
            </span>
          </li>
        </ul>
        <p class="mt-3">
          <.a id="report-start-all" navigate={~p"/teams/#{@current_team}/reports?show=built-in"}>{all_built_in(
            @current_team
          )}</.a>
        </p>
        <p class="action mt-8">
          <.a id="report-write-own" href="#" phx-click="write_own">Write the query yourself</.a>
        </p>
      </section>
      <.form for={@form} id="report-form" phx-change="change" phx-submit="save">
        <.error_summary form={@form} />
        <div :if={@renaming} id="report-names" phx-mounted={JS.focus(to: "#report_name")}>
          <.name_fields form={@form} />
          <div :if={@rename_from} id="report-rename-actions" class="flex gap-3">
            <.button
              id="report-rename-keep"
              type="button"
              variant={:success}
              phx-click="rename_keep"
            >
              Rename
            </.button>
            <.button id="report-rename-cancel" type="button" phx-click="rename_cancel">
              Cancel
            </.button>
          </div>
        </div>
        <div :if={!@renaming} id="report-names-hidden" hidden>
          <.name_fields form={@form} />
        </div>
        <div id="report-body" class={(@rename_from || @starting) && "hidden"}>
          <.input
            :if={change_field?(assigns)}
            field={@form[:change]}
            type="text"
            label="What changed (optional)"
            maxlength={SavedReport.max_change()}
          >
            One line in the report's History.
          </.input>

          <p :if={query_toggle?(assigns)} id="report-query-toggle" class="action mb-6">
            <.a
              :if={!query_shown?(assigns)}
              id="report-show-query"
              href="#"
              phx-click="show_query"
            >Show query</.a>
            <.a
              :if={query_shown?(assigns)}
              id="report-hide-query"
              href="#"
              phx-click="hide_query"
            >Hide query</.a>
          </p>
          <.input
            field={@form[:query]}
            field_class={!query_shown?(assigns) && "hidden"}
            type="textarea"
            label="Query"
            rows="9"
            class="font-mono"
            phx-debounce="300"
            spellcheck="false"
          >
            Write :year for a value you pick each time it runs. For one member, use their ID: member.ref_id = '112'.
          </.input>
          <.field_buttons
            :if={query_shown?(assigns) and !@rename_from}
            subject={@subject}
            context={@context}
            team={@current_team}
          />

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
              count={preview_count(@view, query_shown?(assigns))}
            />
          </div>
        </div>
      </.form>
    </.ai_editor>
    """
  end

  attr :subject, :map, required: true
  attr :context, :any, required: true
  attr :team, :any, required: true

  # The subject's fields under the query, SAR Duty's own and then the team's custom
  # fields, each a button that puts it where the cursor is; its title says what it is.
  defp field_buttons(assigns) do
    ~H"""
    <div id="report-fields" class="mb-6">
      <div class="label mb-1">Fields in {@subject.name}</div>
      <p class="hint mb-2">Click a field to add it where the cursor is.</p>
      <div
        id="report-field-list"
        phx-hook="InsertField"
        data-target="report_query"
        class="flex flex-wrap gap-2"
      >
        <.button
          :for={field <- shown_fields(@subject, @context)}
          id={field_id(field)}
          type="button"
          size={:sm}
          data-field={Expr.example(field)}
          title={field.about || field.label}
        >
          {Expr.example(field)}
        </.button>
      </div>
      <p class="hint mt-3">
        <.a id="report-language-link" href={~p"/agents/reports"} external={true}>How to write a report</.a>
        ·
        <.a id="report-charts-link" href={~p"/agents/reports" <> "#charts"} external={true}>What each chart takes</.a>
        ·
        <.a id="report-field-meanings" navigate={~p"/teams/#{@team}/settings/fields"}>What each field means</.a>
      </p>
    </div>
    """
  end

  defp shown_fields(subject, context) do
    {custom, own} = subject |> Catalog.shown_fields(context) |> Enum.split_with(& &1.custom)
    own ++ custom
  end

  defp field_id(%{custom: %{ids: ids}}), do: "custom-field-#{Enum.join(ids, "-")}"
  defp field_id(field), do: "field-#{field.name}"

  defp ai_sees,
    do:
      "AI works only with the report language and your team's field names. Agents never see your team's members or records."

  defp ai_closed_text(:ok), do: nil
  defp ai_closed_text({:error, :daily_limit}), do: ai_error_text(:daily_limit)
  defp ai_closed_text({:error, reason}), do: ai_error_text(reason)

  defp all_built_in(team) do
    team
    |> BuiltIn.for_team()
    |> length()
    |> Format.count(one: "The %d built-in report", many: "All %d built-in reports")
  end

  # The chart a built-in report ends with, as its icon, or nil.
  defp chart_icon(report) do
    case Parser.parse(report.query) do
      {:ok, %{chart: %{kind: kind}}} -> Map.get(@chart_icons, kind)
      _no_chart -> nil
    end
  end

  attr :form, :map, required: true

  defp name_fields(assigns) do
    ~H"""
    <.input field={@form[:name]} type="text" label="Name" maxlength="80" />
    <.input field={@form[:about]} type="text" label="Description" maxlength="200">
      One line under the name on Reports.
    </.input>
    """
  end

  # The name as it stands is the page's title; until there is one, New report.
  defp title(form, page_title), do: blank_or(form[:name].value, page_title)
  defp about(form), do: blank_or(form[:about].value, nil)

  defp blank_or(value, default) do
    case String.trim(value || "") do
      "" -> default
      text -> text
    end
  end

  # AI writes the query, so it can be folded; a mistake shows it.
  defp query_shown?(assigns), do: assigns.query_open or assigns.query_error != nil

  # Show query and Hide query, while AI writing writes it. A mistake keeps the query open,
  # so there is nothing to toggle then.
  defp query_toggle?(assigns), do: assigns.ai == :ok and assigns.query_error == nil

  # AI writing beside the report: open to the admin, past the blank start, not renaming.
  defp ai_column?(assigns),
    do: assigns.ai != {:error, :off} and !assigns.starting and assigns.rename_from == nil

  # What changed, unless AI writes the History line.
  defp change_field?(assigns), do: assigns.saved != nil and !assigns.ai_line

  defp cancel_path(team, nil), do: ~p"/teams/#{team}/reports"
  defp cancel_path(team, saved), do: ~p"/teams/#{team}/reports/#{saved.id}"

  # The picks the preview's tiles and headers keep, as the form saves them.
  defp picks(nil), do: []

  defp picks(view) do
    switch = if view.switch, do: [{view.switch.name, view.switch.picked}], else: []
    sort = if view.sort, do: [{"sort", view.sort}], else: []
    switch ++ sort
  end

  # The count, how many show, and "runs as you type" while the query shows: nothing to
  # say about typing while it is folded.
  defp preview_count(view, typing?) do
    shown = length(view.result.rows)
    first = if view.total > shown, do: "shows the first #{Format.number(shown)}"
    typing = if typing?, do: "runs as you type"

    [ReportPage.count(view), first, typing]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end
end

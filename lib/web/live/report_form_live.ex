defmodule Web.ReportFormLive do
  @moduledoc """
  New report and Change report (#768). The query first, its rows as you type, then the
  name: a report is named once it's right. Save keeps the query and the picked values,
  never the rows. Beside the query, the fields of the subject after `from`; a click puts
  one in the query where the cursor is. `?from=<id>` starts from a copy of another
  report, such as a built-in one.
  """
  use Web, :live_view_app_layout

  import Web.Components.ReportTable

  alias App.Model.SavedReport
  alias App.Operation.SaveReport
  alias App.Report
  alias App.Report.Catalog
  alias App.Report.Error
  alias App.Report.Parser
  alias App.Report.Result
  alias App.ViewData.ReportRecords
  alias App.ViewData.Reports
  alias Service.Format

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
      subject: Catalog.subject("members")
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

  defp start(:new, _params, _team, _now), do: {nil, %{"query" => @first_query}}

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
      |> assign_preview(Report.run(query, team, values, socket.assigns.now))
    end
  end

  defp assign_preview(socket, {:ok, %Result{} = result}) do
    shown = %{result | rows: Enum.take(result.rows, @preview_rows), totals: nil}

    assign(socket,
      result: shown,
      total_rows: length(result.rows),
      records: ReportRecords.load(shown, socket.assigns.current_team, socket.assigns.now),
      query_error: nil
    )
  end

  defp assign_preview(socket, {:error, %Error{} = error}),
    do: assign(socket, result: nil, query_error: Error.text(error))

  defp subject(query) do
    case Parser.parse(query) do
      {:ok, %{from: from}} -> Catalog.subject(from)
      {:error, _error} -> nil
    end
  end

  # The query's mistake goes on its field as you type, as Save would put it there.
  def handle_event("change", %{"report" => params}, socket) do
    socket = preview(socket, params)
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
        <h2 class="heading">Fields in {@subject.name}</h2>
        <p class="hint">Click a field to add it where the cursor is.</p>
        <div id="report-field-list" phx-hook="InsertField" data-target="report_query">
          <.table
            id="report-field-table"
            rows={Catalog.shown_fields(@subject)}
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
            :for={value <- (@result && @result.values) || []}
            value={value}
            id={"report-form-value-#{value.name}"}
            name={"report[values][#{value.name}]"}
          />

          <div :if={@result} id="report-preview" class="mb-8">
            <p id="report-preview-count" class="hint">{preview_count(@result, @total_rows)}</p>
            <.report_table
              :if={@result.rows != []}
              id="report-preview-rows"
              result={@result}
              records={@records}
              team={@current_team}
              now={@now}
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

  defp field_text(%{args: [_ | _]} = field), do: "#{field.name}(365)"
  defp field_text(field), do: field.name

  defp cancel_path(team, nil), do: ~p"/teams/#{team}/reports"
  defp cancel_path(team, saved), do: ~p"/teams/#{team}/reports/#{saved.id}"

  defp preview_count(result, total) do
    count = Web.ReportLive.count(%{result | rows: List.duplicate(nil, total)})

    if total > @preview_rows,
      do: "#{count} · shows the first #{Format.number(@preview_rows)} · runs as you type",
      else: "#{count} · runs as you type"
  end
end

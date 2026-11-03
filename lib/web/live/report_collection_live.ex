defmodule Web.ReportCollectionLive do
  @moduledoc """
  Reports (#768): every report a team admin can run, the team's own and the ones built
  into SAR Duty (App.Report.BuiltIn), in one table. The counts above it show all, the
  built-in ones, or the team's own; Report, Shows, and Date sort it. Recently deleted, a
  count shown only when there is one, lists the team's deleted reports for 30 days, each
  with Restore (#834).
  """
  use Web, :live_view_app_layout

  import Web.Components.StatSwitch

  alias App.Model.SavedReport
  alias App.Operation.SaveReport
  alias App.ViewData.Reports
  alias Service.Format

  @views [{"All", nil}, {"Built in", "built-in"}, {"Your team's", "team"}]
  @sorts ~w(name shows date-)

  def mount(_params, _session, socket),
    do: {:ok, socket |> assign(page_title: "Reports") |> load()}

  defp load(socket) do
    reports = Reports.list(socket.assigns.current_team, DateTime.utc_now())
    assign(socket, reports: reports.saved ++ reports.built_in, deleted: reports.deleted)
  end

  def handle_params(params, _uri, socket) do
    view = if params["show"] in ["built-in", "team", "deleted"], do: params["show"], else: nil
    sort = if params["sort"] in @sorts, do: params["sort"], else: "name"
    {:noreply, assign_rows(socket, %{show: view, sort: sort})}
  end

  defp assign_rows(socket, %{show: view, sort: sort} = options) do
    %{reports: reports, deleted: deleted} = socket.assigns
    rows = if view == "deleted", do: deleted, else: Enum.filter(reports, &shown?(&1, view))

    assign(socket,
      options: options,
      rows: sort(rows, sort),
      views: views(deleted),
      counts:
        @views
        |> Map.new(fn {_label, v} -> {v, Enum.count(reports, &shown?(&1, v))} end)
        |> Map.put("deleted", length(deleted)),
      path_fn: path_fn(socket.assigns.current_team, options)
    )
  end

  # Recently deleted, only while there is one.
  defp views([]), do: @views
  defp views(_deleted), do: Enum.concat(@views, [{"Recently deleted", "deleted"}])

  def handle_event("restore", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id),
         {:ok, report} <- SaveReport.restore(socket.assigns.current_team, id) do
      {:noreply,
       socket
       |> load()
       |> assign_rows(socket.assigns.options)
       |> put_flash(:info, "Restored the #{report.name} report.")}
    else
      _not_found -> {:noreply, socket |> load() |> assign_rows(socket.assigns.options)}
    end
  end

  defp shown?(_report, nil), do: true
  defp shown?(report, "built-in"), do: is_nil(report.saved)
  defp shown?(report, "team"), do: not is_nil(report.saved)

  defp sort(reports, "name"), do: Enum.sort_by(reports, &String.downcase(&1.name))

  defp sort(reports, "shows"),
    do: Enum.sort_by(reports, &{String.downcase(&1.shows || ""), String.downcase(&1.name)})

  # Newest first; the built-in ones have no date, so they come last, by name.
  defp sort(reports, "date-"),
    do:
      Enum.sort_by(reports, fn r ->
        {is_nil(r.made_on), -DateTime.to_unix(r.made_on || ~U[1970-01-01 00:00:00Z]),
         String.downcase(r.name)}
      end)

  # A path with the options, leaving out the defaults. The table passes `page`, which this
  # list has none of.
  defp path_fn(team, options) do
    fn changes ->
      params =
        options
        |> Map.merge(changes |> Keyword.delete(:page) |> Map.new())
        |> Enum.reject(fn {key, value} -> is_nil(value) or {key, value} == {:sort, "name"} end)

      ~p"/teams/#{team}/reports?#{params}"
    end
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

    <.stat_switch id="report-switch" label="Reports">
      <:view
        :for={{label, view} <- @views}
        id={"report-view-#{view || "all"}"}
        patch={@path_fn.(show: view)}
        current={@options.show == view}
        count={@counts[view]}
      >
        {label}
      </:view>
    </.stat_switch>

    <p :if={@options.show == "deleted"} id="reports-deleted-hint" class="hint">
      A deleted report stays here for {Format.days(SavedReport.deleted_days())} with its History, then goes for good.
    </p>

    <.table
      :if={@rows != []}
      id="reports"
      rows={@rows}
      row_id={&"report-#{&1.id}"}
      sort={@options.sort}
      path_fn={@path_fn}
      class="table-striped"
    >
      <:col :let={report} label="Report" sorts={[{"↑", "name"}]}>
        <div :if={@options.show == "deleted"} class="flex items-center gap-3">
          <span>{report.name}</span>
          <.button
            id={"report-restore-#{report.id}"}
            type="button"
            size={:sm}
            phx-click="restore"
            phx-value-id={report.id}
          >
            Restore
          </.button>
        </div>
        <.a
          :if={@options.show != "deleted"}
          navigate={~p"/teams/#{@current_team}/reports/#{report.id}"}
        >{report.name}</.a>
        <div :if={report.about} class="hint">{report.about}</div>
      </:col>
      <:col :let={report} label="Shows" class="w-px whitespace-nowrap" sorts={[{"↑", "shows"}]}>
        {report.shows}
      </:col>
      <:col :let={report} label="Made by" class="whitespace-nowrap">
        {made_by(report)}
      </:col>
      <:col :let={report} label="Date" class="w-px whitespace-nowrap" sorts={[{"↓", "date-"}]}>
        <.date_cell
          :if={report.made_on}
          value={report.made_on}
          timezone={@current_team.timezone}
        />
      </:col>
    </.table>

    <.empty_state :if={@rows == []} id="reports-empty" title="Your team has no reports yet">
      New report makes one. Copy report on a built-in report starts from that one.
    </.empty_state>
    """
  end

  defp made_by(%{saved: nil}), do: "SAR Duty"
  defp made_by(report), do: report.made_by || "A team admin"
end

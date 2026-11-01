defmodule Web.ActivityCollectionLive do
  @moduledoc """
  Activities, drawn by its report (#784): the tiles, search, filters, sorts, and pages
  are the clauses in `App.Report.Lists.activities/0`, run by `App.Report.page/4`. The
  cells, Add activity, and Save as report stay here.
  """
  use Web, {:live_view_app_layout, access: :team, view_events: ["change"]}

  import Web.Components.ActivityTable
  import Web.Components.ReportPage

  alias App.Model.Attendance
  alias App.Model.ChoreEvent
  alias App.Model.Team
  alias App.Report
  alias App.Report.Error
  alias App.Report.Lists
  alias App.ViewData.ReportRecords
  alias Web.Components.ReportPage

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Activities")}
  end

  # Members open it too (#406) and get the same list, filters, and default as a team
  # admin. Team admins also get Add activity and Save as report.
  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()
    given = Map.drop(params, ["subdomain"])

    case Report.page(Lists.activities().query, team, given, now) do
      {:ok, view} ->
        view = without_chores_tile(view, team)
        activities = activities(view, team, now)

        {:noreply,
         assign(socket,
           view: view,
           activities: activities,
           counts: need_counts(team, activities),
           form: ReportPage.controls_form(view),
           path_fn: &ReportPage.path(view, ~p"/teams/#{team}/activities", &1),
           save_path: ~p"/teams/#{team}/reports/new?#{Map.put(view.params, "list", "activities")}"
         )}

      # The list's own text failing is a bug, not a bad URL; a test runs it.
      {:error, error} ->
        raise "Activities' report: #{Error.text(error)}"
    end
  end

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">Activities</h1>
      <:action>
        <.button
          :if={@team_admin?}
          id="activity-add"
          navigate={~p"/teams/#{@current_team}/activities/new"}
        >
          Add activity
        </.button>
        <.button :if={@team_admin?} id="activity-save-report" navigate={@save_path}>
          Save as report
        </.button>
      </:action>
    </.heading_row>

    <.report_page
      id="activity"
      view={@view}
      records={%{}}
      team={@current_team}
      now={nil}
      path_fn={@path_fn}
      form={@form}
      marker={&marker/1}
    >
      <:table>
        <.activity_table
          rows={@activities}
          sort={@view.sort}
          path_fn={@path_fn}
          team={@current_team}
          hours={picked(@view, "hours")}
          counts={@counts}
        />
      </:table>
    </.report_page>
    """
  end

  def handle_event("change", %{"values" => values}, socket) do
    path = socket.assigns.path_fn.([{:page, nil} | Map.to_list(values)])
    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  # The rows hold the activities' ids; the cells read the activities, each chore activity
  # with its members' minutes (#575).
  defp activities(view, team, now) do
    records = view.result |> ReportRecords.load(team, now) |> Map.get(:activity, %{})

    view.result.rows
    |> Enum.map(fn [id | _] -> Map.fetch!(records, id) end)
    |> ChoreEvent.put_chore_minutes(team.id)
  end

  # Chores only on a team that logs them, or once had chore activities in this view.
  defp without_chores_tile(%{switch: switch} = view, team) do
    chores? =
      Team.chores?(team) or Enum.any?(switch.tiles, &(&1.value == "chores" and &1.count > 0))

    tiles = Enum.reject(switch.tiles, &(&1.value == "chores" and not chores?))
    %{view | switch: %{switch | tiles: tiles}}
  end

  # Each kind's tile has its marker, as the rows show it.
  defp marker("all"), do: nil
  defp marker(kind), do: kind

  defp picked(view, name), do: Enum.find_value(view.filters, &(&1.name == name && &1.picked))

  # The counts for the badges after a title (#447), for activities with Enough at or Full at.
  defp need_counts(team, activities) do
    case for a <- activities, a.enough_at || a.full_at, do: a.id do
      [] -> %{}
      ids -> Attendance.reply_counts(team, ids)
    end
  end
end

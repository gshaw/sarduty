defmodule Web.ProposedChangeCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.StatSwitch

  alias App.Model.ChangeSet

  # Opens on the sets waiting for review; `?view=` picks another part.
  @views ~w(all waiting sent discarded)

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Proposed changes",
       change_sets: ChangeSet.get_proposed(socket.assigns.current_team.id)
     )}
  end

  def handle_params(params, _uri, socket) do
    view = params["view"] || "waiting"
    if view not in @views, do: raise(Web.Status.NotFound)

    counts = Enum.frequencies_by(socket.assigns.change_sets, &part/1)

    {:noreply,
     assign(socket,
       view: view,
       counts: Map.put(counts, "all", length(socket.assigns.change_sets)),
       shown: Enum.filter(socket.assigns.change_sets, &(view == "all" or part(&1) == view))
     )}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Proposed changes" />
    </.breadcrumbs>

    <h1 class="title">Proposed changes</h1>
    <p class="lead">
      An AI agent connected to SAR Duty can propose attendance changes. Nothing changes until a
      team admin reviews them and sends them.
    </p>

    <.stat_switch :if={@change_sets != []} id="proposed-switch" label="Proposed changes">
      <:view
        :for={{view, label} <- views()}
        id={"proposed-view-#{view}"}
        patch={view_path(@current_team, view)}
        current={@view == view}
        count={Map.get(@counts, view, 0)}
      >
        {label}
      </:view>
    </.stat_switch>

    <.table
      :if={@shown != []}
      id="proposed"
      rows={@shown}
      row_id={&"proposed-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={set} label="Proposed" class="w-px whitespace-nowrap">
        {Service.Format.month_day_time(set.inserted_at, @current_team.timezone)}
      </:col>
      <:col :let={set} label="Changes">
        <.a navigate={~p"/teams/#{@current_team}/proposed-changes/#{set.id}"}>{set.summary ||
          "Attendance changes"}</.a>
        <div class="hint">
          {set.activity && set.activity.title} · {Service.Format.count(length(set.rows),
            one: "%d change",
            many: "%d changes"
          )}
        </div>
      </:col>
      <:col :let={set} :if={@view == "all"} label="Status" class="w-px whitespace-nowrap">
        {status(set)}
      </:col>
    </.table>
    <.empty_state :if={@change_sets == []} id="none-proposed" title="No proposed changes yet">
      Changes an AI agent proposes show here for a team admin to send.
    </.empty_state>
    <p :if={@change_sets != [] and @shown == []} id="none-in-view" class="hint">
      {empty_text(@view)}
    </p>
    """
  end

  defp views,
    do: [
      {"all", "All"},
      {"waiting", "Waiting for review"},
      {"sent", "Sent"},
      {"discarded", "Discarded"}
    ]

  defp view_path(team, "waiting"), do: ~p"/teams/#{team}/proposed-changes"
  defp view_path(team, view), do: ~p"/teams/#{team}/proposed-changes?view=#{view}"

  defp part(%ChangeSet{applied_at: %DateTime{}}), do: "sent"
  defp part(%ChangeSet{discarded_at: %DateTime{}}), do: "discarded"
  defp part(%ChangeSet{}), do: "waiting"

  defp status(set), do: views() |> List.keyfind(part(set), 0) |> elem(1)

  defp empty_text("waiting"), do: "Nothing to review."
  defp empty_text("sent"), do: "None sent yet."
  defp empty_text("discarded"), do: "None discarded."
end

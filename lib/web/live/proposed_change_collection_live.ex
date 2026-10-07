defmodule Web.ProposedChangeCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.ChangeSet

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      assign(socket,
        page_title: "Proposed changes",
        waiting: ChangeSet.get_waiting(team.id),
        decided: ChangeSet.get_recent_decided(team.id, 20)
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Proposed changes" />
    </.breadcrumbs>

    <h1 class="title">Proposed changes</h1>
    <p class="text-secondary-1 mb-p">
      An AI agent connected to SAR Duty can propose attendance changes. Nothing changes in D4H
      until a team admin reviews them and sends them.
    </p>

    <.change_set_table
      :if={@waiting != []}
      id="waiting"
      change_sets={@waiting}
      team={@current_team}
    />
    <p :if={@waiting == []} id="none-waiting" class="mb-p">No proposed changes to review.</p>

    <div :if={@decided != []} class="mt-p">
      <h2 class="subheading mb-p05">Reviewed</h2>
      <.change_set_table id="decided" change_sets={@decided} team={@current_team} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :change_sets, :list, required: true
  attr :team, :map, required: true

  defp change_set_table(assigns) do
    ~H"""
    <.table id={@id} rows={@change_sets} row_id={&"#{@id}-#{&1.id}"} class="w-full table-striped">
      <:col :let={set} label="Proposed" class="w-px whitespace-nowrap">
        {Service.Format.month_day_time(set.inserted_at, @team.timezone)}
      </:col>
      <:col :let={set} label="Changes">
        <.a navigate={~p"/teams/#{@team}/proposed-changes/#{set.id}"}>
          {set.summary || "Attendance changes"}
        </.a>
        <div class="text-secondary-1">
          {set.activity && set.activity.title} · {Service.Format.count(length(set.rows),
            one: "%d change",
            many: "%d changes"
          )}
        </div>
      </:col>
      <:col :let={set} label="Status" class="w-px whitespace-nowrap">
        {status(set)}
      </:col>
    </.table>
    """
  end

  defp status(%ChangeSet{applied_at: %DateTime{}}), do: "Sent to D4H"
  defp status(%ChangeSet{discarded_at: %DateTime{}}), do: "Discarded"
  defp status(%ChangeSet{}), do: "Waiting for review"
end

defmodule Web.WhiteboardLive do
  use Web, {:live_view_app_layout, access: :team}

  import Web.Components.Pagination
  import Web.Components.StatSwitch

  alias App.Model.WhiteboardNote
  alias Web.WhiteboardText

  # Every note on the team's whiteboard (#515), /teams/:subdomain/whiteboard, from the
  # Dashboard card's All notes. Everyone on the team reads it. Archived is the only place
  # a SAR Duty Records team can see old notes. Team admins get Change and Archive on the
  # team's live notes, Post again on every archived note, and Delete on the team's own.
  @views [live: "On the whiteboard", archived: "Archived"]

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !team.whiteboard_enabled, do: raise(Web.Status.NotFound)

    {:ok, assign(socket, page_title: "Whiteboard", org_name: WhiteboardText.org_name(team))}
  end

  def handle_params(params, _uri, socket) do
    view = if params["view"] == "archived", do: :archived, else: :live
    page = parse_page(params["page"])

    socket
    |> assign(view: view, page: page)
    |> load()
    |> then(&{:noreply, &1})
  end

  @doc "The Whiteboard page showing live or archived notes."
  def view_path(team, view, page \\ 1)
  def view_path(team, :live, _page), do: ~p"/teams/#{team}/whiteboard"
  def view_path(team, :archived, 1), do: ~p"/teams/#{team}/whiteboard?view=archived"

  def view_path(team, :archived, page),
    do: ~p"/teams/#{team}/whiteboard?#{[view: :archived, page: page]}"

  defp load(socket) do
    %{current_team: team, view: view, page: page} = socket.assigns
    now = DateTime.utc_now()

    {notes, paginated} =
      case view do
        :live ->
          {WhiteboardNote.live(team, now), nil}

        :archived ->
          paginated = WhiteboardNote.archived(team, now, page)
          {paginated.entries, paginated}
      end

    assign(socket,
      notes: notes,
      paginated: paginated,
      counts: WhiteboardNote.counts(team, now),
      today: Service.Period.today(now, team.timezone)
    )
  end

  defp parse_page(nil), do: 1

  defp parse_page(page) do
    case Integer.parse(page) do
      {number, ""} when number > 0 -> number
      _other -> 1
    end
  end

  def render(assigns) do
    assigns = assign(assigns, views: @views)

    ~H"""
    <.breadcrumbs>
      <:item label="Dashboard" path={~p"/teams/#{@current_team}"} />
      <:item label="Whiteboard" />
    </.breadcrumbs>
    <.heading_row>
      <h1 class="title">Whiteboard</h1>
      <:action :if={@team_admin?}>
        <.button id="whiteboard-post" navigate={~p"/teams/#{@current_team}/whiteboard/new"}>
          Post a note
        </.button>
      </:action>
    </.heading_row>
    <p class="lead measure">
      Short notes for everyone on the team. A note leaves the whiteboard after its last day, and stays here under Archived.
    </p>

    <.stat_switch id="whiteboard-switch" label="Notes">
      <:view
        :for={{view, label} <- @views}
        id={"whiteboard-view-#{view}"}
        patch={view_path(@current_team, view)}
        current={@view == view}
        count={Map.fetch!(@counts, view)}
      >
        {label}
      </:view>
    </.stat_switch>

    <.empty_state
      :if={@notes == [] and @view == :live}
      id="whiteboard-empty"
      title="No notes on the whiteboard"
    >
      <span :if={@team_admin?}>Post one for everyone on the team to read.</span>
    </.empty_state>
    <.empty_state
      :if={@notes == [] and @view == :archived}
      id="whiteboard-empty"
      title="No archived notes"
    >
      A note shows here after its last day.
    </.empty_state>

    <.table
      :if={@notes != []}
      id="whiteboard-notes"
      rows={@notes}
      row_id={&"whiteboard-note-#{&1.id}"}
      class="table-stack"
    >
      <:col :let={note} label="Note" class="stack-full">
        <WhiteboardText.note_text note={note} />
        <WhiteboardText.note_link note={note} class="block" />
        <span :if={note.owner_kind == :organization} class="hint block">
          {WhiteboardText.from(@org_name)}
        </span>
      </:col>
      <:col :let={note} label="Posted" class="whitespace-nowrap">
        {WhiteboardText.posted(note, @current_team.timezone, @today)}
      </:col>
      <:col :let={note} label="Until" class="whitespace-nowrap">
        {WhiteboardText.until(note, @current_team.timezone, @today)}
      </:col>
      <:col :let={note} :if={@team_admin?} label="" class="whitespace-nowrap">
        <span :if={@view == :live and WhiteboardNote.team_note?(note)} class="flex gap-3">
          <.button
            id={"whiteboard-change-#{note.id}"}
            size={:sm}
            navigate={~p"/teams/#{@current_team}/whiteboard/#{note.id}/edit"}
          >
            Change
          </.button>
          <.button
            id={"whiteboard-archive-#{note.id}"}
            size={:sm}
            type="button"
            phx-click="archive"
            phx-value-id={note.id}
            data-confirm={WhiteboardText.archive_confirm()}
          >
            Archive
          </.button>
        </span>
        <span :if={@view == :archived} class="flex gap-3">
          <.button
            id={"whiteboard-again-#{note.id}"}
            size={:sm}
            navigate={~p"/teams/#{@current_team}/whiteboard/new?#{[from: note.id]}"}
          >
            Post again
          </.button>
          <.button
            :if={WhiteboardNote.team_note?(note)}
            id={"whiteboard-delete-#{note.id}"}
            size={:sm}
            type="button"
            phx-click="delete"
            phx-value-id={note.id}
            data-confirm={"Delete this note? #{Web.WhiteboardNoteFormLive.gone_text(@current_team)}"}
          >
            Delete
          </.button>
        </span>
      </:col>
    </.table>

    <.pagination
      :if={@paginated}
      class="my-4"
      paginated={@paginated}
      path_fn={fn [page: page] -> view_path(@current_team, :archived, page) end}
    />
    """
  end

  # Only team admins see the buttons, but an event can still come from a member's page.
  def handle_event(_event, _params, %{assigns: %{team_admin?: false}} = socket),
    do: {:noreply, socket}

  def handle_event("archive", %{"id" => id}, socket),
    do: act(socket, &WhiteboardText.archive/3, id)

  def handle_event("delete", %{"id" => id}, socket), do: act(socket, &WhiteboardText.delete/3, id)

  defp act(socket, fun, id) do
    %{current_team: team, current_user: user} = socket.assigns

    case fun.(team, user, id) do
      :ok -> {:noreply, load(socket)}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end
end

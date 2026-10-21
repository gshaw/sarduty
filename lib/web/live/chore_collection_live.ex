defmodule Web.ChoreCollectionLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Operation.SaveChore
  alias Service.Format

  # The team's chores (#341), /teams/:subdomain/chores: every waiting chore, from any
  # month, to accept in one step with the Review changes pattern. Every row starts
  # selected; a cleared row stays waiting. Then what is in D4H: one event per month and
  # chore category, rebuilt by the nightly send.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !team.member_logins, do: raise(Web.Status.NotFound)

    socket
    |> assign(service: D4H.service_name(team))
    |> assign(
      page_title: "Chores",
      today: Service.Period.today(DateTime.utc_now(), team.timezone)
    )
    |> load()
    |> then(&{:ok, &1})
  end

  defp load(socket) do
    waiting = Chore.get_waiting(socket.assigns.current_team.id)

    assign(socket,
      waiting: waiting,
      events: ChoreEvent.get_all_with_totals(socket.assigns.current_team.id),
      selected: MapSet.new(waiting, & &1.id),
      chore_count: length(waiting)
    )
  end

  @doc "When it was logged, under its date, only when that was a later month."
  def logged_note(chore, timezone) do
    logged = Service.Period.today(chore.inserted_at, timezone)

    if Date.beginning_of_month(logged) != Date.beginning_of_month(chore.date),
      do: "Logged #{Format.date_short(logged)}"
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">Chores</h1>
    <p class="lead measure">
      Accept a chore to count it. SAR Duty sends accepted chores to {@service} every night.
    </p>

    <h2 class="subheading mt-8">Waiting · {length(@waiting)}</h2>
    <.empty_state :if={@waiting == []} id="no-waiting-chores" title="No chores waiting">
      Chores members log show here for you to accept.
    </.empty_state>

    <div :if={@waiting != []}>
      <p class="hint mb-4">
        Clear the box next to a chore to leave it waiting. Open a chore to change or decline it.
      </p>
      <.form for={%{}} id="accept-form" phx-change="select" phx-submit="accept">
        <.table
          id="waiting-chores"
          rows={@waiting}
          row_id={&"chore-#{&1.id}"}
          class="table-striped table-stack"
        >
          <:col :let={chore} label="" class="w-px stack-check" select_all>
            <input
              type="checkbox"
              id={"select-#{chore.id}"}
              name="chore_ids[]"
              value={chore.id}
              checked={MapSet.member?(@selected, chore.id)}
              aria-label={"Accept #{chore.description}"}
            />
          </:col>
          <:col :let={chore} label="Member" class="stack-title">{chore.member.name}</:col>
          <:col :let={chore} label="Date" class="whitespace-nowrap">
            {Format.day_in_year(chore.date, @today)}
            <span :if={note = logged_note(chore, @current_team.timezone)} class="hint block">
              {note}
            </span>
          </:col>
          <:col :let={chore} label="What they did" class="stack-full">
            <.a navigate={~p"/teams/#{@current_team}/chores/#{chore.id}"}>{chore.description}</.a>
          </:col>
          <:col :let={chore} label="Category">{chore.chore_category.title}</:col>
          <:col :let={chore} label="Time" class="whitespace-nowrap" align="right">
            {Format.duration(chore.minutes)}
          </:col>
        </.table>

        <.form_actions>
          <.button
            id="accept"
            variant={:success}
            disabled={MapSet.size(@selected) == 0}
            phx-disable-with="Accepting…"
          >
            Accept {count_chores(MapSet.size(@selected))}
          </.button>
        </.form_actions>
      </.form>
    </div>

    <h2 class="subheading mt-8">In {@service}</h2>
    <p class="hint mb-4">
      One event per month and category. Each send rebuilds the event from its accepted chores, so edits made in {@service} are replaced.
    </p>
    <.empty_state :if={@events == []} id="no-chore-events" title="Nothing sent yet">
      Accepted chores go to {@service} the night after you accept them.
    </.empty_state>
    <.table
      :if={@events != []}
      id="chore-events"
      rows={@events}
      row_id={&"chore-event-#{&1.event.id}"}
      class="table-striped table-stack"
    >
      <:col :let={row} label="Month" class="whitespace-nowrap">
        {Format.month_year_long(row.event.month)}
      </:col>
      <:col :let={row} label="Category" class="stack-title">
        {row.event.chore_category.title}
      </:col>
      <:col :let={row} label="Members" align="right">{Format.number(row.members)}</:col>
      <:col :let={row} label="Hours" class="whitespace-nowrap" align="right">
        {Format.duration(row.minutes)}
      </:col>
      <:col :let={row} label="Event">
        <.a :if={row.activity} navigate={~p"/teams/#{@current_team}/activities/#{row.activity.id}"}>
          {row.activity.ref_id}
        </.a>
        <span :if={!row.activity and row.event.d4h_activity_id} class="hint">
          Refreshing from {@service}
        </span>
      </:col>
      <:col :let={row} label="Sent" class="whitespace-nowrap">
        <.badge :if={row.event.needs_send} kind={:primary}>Tonight</.badge>
        <span :if={!row.event.needs_send and row.event.sent_at}>
          {Format.date_short(row.event.sent_at, @current_team.timezone)}
        </span>
        <span :if={row.event.send_error} class="hint block">{row.event.send_error}</span>
      </:col>
    </.table>
    """
  end

  def handle_event("select", params, socket),
    do: {:noreply, assign(socket, :selected, params |> selected_ids() |> MapSet.new())}

  def handle_event("accept", params, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case selected_ids(params) do
      [] ->
        {:noreply, put_flash(socket, :error, "Select at least 1 chore to accept.")}

      ids ->
        count = SaveChore.accept(team, ids, user, DateTime.utc_now())

        socket
        |> put_flash(:info, "Accepted #{count_chores(count)}.")
        |> load()
        |> then(&{:noreply, &1})
    end
  end

  defp selected_ids(params) do
    params
    |> Map.get("chore_ids", [])
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {id, ""} -> [id]
        _other -> []
      end
    end)
  end

  defp count_chores(n), do: Format.count(n, one: "%d chore", many: "%d chores")
end

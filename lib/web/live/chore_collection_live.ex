defmodule Web.ChoreCollectionLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Operation.SaveChore
  alias App.Operation.SendChores
  alias Service.Format

  # The team's chores (#341), /teams/:subdomain/chores. Waiting chores to accept, accepted
  # ones to send to D4H when a team admin chooses, and what is in D4H. Both lists use the
  # Review changes pattern: every row starts selected, and a cleared row stays.
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
    team_id = socket.assigns.current_team.id
    waiting = Chore.get_waiting(team_id)
    ready = Chore.get_ready(team_id)

    assign(socket,
      waiting: waiting,
      ready: ready,
      events: ChoreEvent.get_all_with_totals(team_id),
      selected: MapSet.new(waiting, & &1.id),
      to_send: MapSet.new(ready, & &1.id),
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
      Accept a chore to count it. Send accepted chores to {@service} when you are ready.
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
        <.chore_table
          id="waiting-chores"
          chores={@waiting}
          name="chore_ids[]"
          selected={@selected}
          today={@today}
          current_team={@current_team}
        />
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

    <h2 class="subheading mt-8">Ready to send · {length(@ready)}</h2>
    <.empty_state :if={@ready == []} id="no-ready-chores" title="Nothing to send">
      Chores you accept wait here until you send them to {@service}.
    </.empty_state>

    <div :if={@ready != []}>
      <p class="hint mb-4">
        A send makes one {@service} activity for each category and year, dated on its last chore.
      </p>
      <.form for={%{}} id="send-form" phx-change="select-send" phx-submit="send">
        <.chore_table
          id="ready-chores"
          chores={@ready}
          name="send_ids[]"
          selected={@to_send}
          today={@today}
          current_team={@current_team}
        />
        <.form_actions>
          <.button
            id="send"
            variant={:primary}
            disabled={MapSet.size(@to_send) == 0 || is_nil(@current_team.d4h_access_key)}
            phx-disable-with={"Sending to #{@service}…"}
          >
            Send {count_chores(MapSet.size(@to_send))}
          </.button>
        </.form_actions>
      </.form>
    </div>

    <h2 class="subheading mt-8">In {@service}</h2>
    <p :if={@events != []} class="hint mb-4">
      Change a sent chore here, then send the changes. Edits made in {@service} are replaced.
    </p>
    <.empty_state :if={@events == []} id="no-chore-events" title="Nothing sent yet">
      Chores you send show here, with a link to each {@service} activity.
    </.empty_state>
    <.table
      :if={@events != []}
      id="chore-events"
      rows={@events}
      row_id={&"chore-event-#{&1.event.id}"}
      class="table-striped table-stack"
    >
      <:col :let={row} label="Date" class="whitespace-nowrap">
        {row.date && Format.day_in_year(row.date, @today)}
      </:col>
      <:col :let={row} label="Category" class="stack-title">
        {row.event.chore_category.title}
      </:col>
      <:col :let={row} label="Members" align="right">{Format.number(row.members)}</:col>
      <:col :let={row} label="Hours" class="whitespace-nowrap" align="right">
        {Format.duration(row.minutes)}
      </:col>
      <:col :let={row} label="Activity">
        <.a :if={row.activity} navigate={~p"/teams/#{@current_team}/activities/#{row.activity.id}"}>
          {row.activity.ref_id}
        </.a>
        <span :if={!row.activity and row.event.d4h_activity_id} class="hint">
          Refreshing from {@service}
        </span>
      </:col>
      <:col :let={row} label="Sent" class="stack-full">
        <span :if={row.event.sent_at} class="whitespace-nowrap">
          {Format.date_short(row.event.sent_at, @current_team.timezone)}
        </span>
        <span :if={row.event.send_note} class="hint block">{row.event.send_note}</span>
        <.button
          :if={row.event.needs_send}
          id={"send-changes-#{row.event.id}"}
          type="button"
          size={:sm}
          phx-click="send-changes"
          phx-value-id={row.event.id}
          phx-disable-with="Sending…"
        >
          Send changes
        </.button>
      </:col>
    </.table>
    """
  end

  attr :id, :string, required: true
  attr :chores, :list, required: true
  attr :name, :string, required: true
  attr :selected, :any, required: true
  attr :today, :any, required: true
  attr :current_team, :map, required: true

  # Chores with a box each, for accepting or sending.
  defp chore_table(assigns) do
    ~H"""
    <.table id={@id} rows={@chores} row_id={&"chore-#{&1.id}"} class="table-striped table-stack">
      <:col :let={chore} label="" class="w-px stack-check" select_all>
        <input
          type="checkbox"
          id={"#{@id}-select-#{chore.id}"}
          name={@name}
          value={chore.id}
          checked={MapSet.member?(@selected, chore.id)}
          aria-label={"Select #{chore.description}"}
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
    """
  end

  def handle_event("select", params, socket),
    do: {:noreply, assign(socket, :selected, params |> ids("chore_ids") |> MapSet.new())}

  def handle_event("select-send", params, socket),
    do: {:noreply, assign(socket, :to_send, params |> ids("send_ids") |> MapSet.new())}

  def handle_event("accept", params, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case ids(params, "chore_ids") do
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

  def handle_event("send", params, socket) do
    %{current_team: team, current_user: user, service: service} = socket.assigns

    case ids(params, "send_ids") do
      [] ->
        {:noreply, put_flash(socket, :error, "Select at least 1 chore to send.")}

      ids ->
        result = SendChores.call(team, ids, user, DateTime.utc_now())

        socket
        |> put_send_flash(result, service)
        |> load()
        |> then(&{:noreply, &1})
    end
  end

  def handle_event("send-changes", %{"id" => id}, socket) do
    %{current_team: team, current_user: user, service: service} = socket.assigns
    event = ChoreEvent.find!(team, id)

    socket =
      case SendChores.send_changes(team, event, user, DateTime.utc_now()) do
        :sent -> put_flash(socket, :info, "Changes sent to #{service}.")
        :failed -> put_flash(socket, :error, "Changes not sent. The reason is in the table.")
        :locked -> put_flash(socket, :error, "Changes not sent. D4H has approved the activity.")
      end

    {:noreply, load(socket)}
  end

  defp put_send_flash(socket, %{failed: 0} = result, service) do
    activities = Format.count(result.events, one: "1 activity", many: "%d activities")

    put_flash(
      socket,
      :info,
      "Sent #{count_chores(result.chores)} to #{service} as #{activities}."
    )
  end

  defp put_send_flash(socket, result, _service) do
    message =
      Format.count(result.failed,
        one: "1 activity did not go through. The reason is in the table.",
        many: "%d activities did not go through. The reasons are in the table."
      )

    put_flash(socket, :error, message)
  end

  defp ids(params, key) do
    params
    |> Map.get(key, [])
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {id, ""} -> [id]
        _other -> []
      end
    end)
  end

  defp count_chores(n), do: Format.count(n, one: "%d chore", many: "%d chores")
end

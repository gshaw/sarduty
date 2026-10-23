defmodule Web.ChoreCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.StatSwitch

  alias App.Adapter.D4H
  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Model.Team
  alias App.Operation.SaveChore
  alias App.Operation.SendChores
  alias Service.Format
  alias Web.ChoreText

  # The team's chores (#341), /teams/:subdomain/chores, by status. Waiting chores to accept,
  # with the Review changes pattern: every row starts selected, and a cleared row stays.
  # Accepting sends them to D4H, onto each chore category's activity for the month, and
  # Accepted lists them under those activities. Every chore opens its own page, to change
  # or decline it.
  @views [waiting: "Waiting", accepted: "Accepted", declined: "Declined"]

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !Team.chores?(team), do: raise(Web.Status.NotFound)

    socket
    |> assign(service: D4H.service_name(team))
    |> assign(
      page_title: "Chores",
      today: Service.Period.today(DateTime.utc_now(), team.timezone)
    )
    |> then(&{:ok, &1})
  end

  def handle_params(params, _uri, socket) do
    wanted = params["view"] || "waiting"
    view = @views |> Keyword.keys() |> Enum.find(&(Atom.to_string(&1) == wanted))
    if !view, do: raise(Web.Status.NotFound)

    socket
    |> assign(view: view)
    |> load()
    |> then(&{:noreply, &1})
  end

  @doc "The Chores page showing chores in `status`."
  def view_path(team, :waiting), do: ~p"/teams/#{team}/chores"
  def view_path(team, status), do: ~p"/teams/#{team}/chores?#{[view: status]}"

  defp load(socket) do
    team_id = socket.assigns.current_team.id
    counts = Chore.count_by_status(team_id)

    socket
    |> assign(
      counts: counts,
      to_send: ChoreEvent.count_to_send(team_id),
      chore_count: counts.waiting
    )
    |> load_view(socket.assigns.view, team_id)
  end

  defp load_view(socket, :waiting, team_id) do
    waiting = Chore.get_all_for_team(team_id, :waiting)
    assign(socket, chores: waiting, selected: MapSet.new(waiting, & &1.id))
  end

  defp load_view(socket, :accepted, team_id) do
    by_event = team_id |> Chore.get_all_for_team(:accepted) |> Enum.group_by(& &1.chore_event_id)

    events =
      for row <- ChoreEvent.get_all_with_totals(team_id),
          do: Map.put(row, :chores, Map.get(by_event, row.event.id, []))

    assign(socket, events: events)
  end

  defp load_view(socket, :declined, team_id),
    do: assign(socket, chores: Chore.get_all_for_team(team_id, :declined))

  @doc "When it was logged, under its date, only when that was a later month."
  def logged_note(chore, timezone) do
    logged = Service.Period.today(chore.inserted_at, timezone)

    if Date.beginning_of_month(logged) != Date.beginning_of_month(chore.date),
      do: "Logged #{Format.date_short(logged)}"
  end

  def render(assigns) do
    assigns = assign(assigns, views: @views)

    ~H"""
    <h1 class="title">Chores</h1>
    <p class="lead measure">
      Accepting a chore counts it and sends it to {@service}. Each chore category gets one {@service} activity a month.
    </p>

    <.banner :if={@to_send > 0} kind={:warning} title="Changes not sent" id="chores-to-send">
      <p>
        {Format.count(@to_send,
          one: "1 activity in #{@service} is out of date.",
          many: "%d activities in #{@service} are out of date."
        )}
      </p>
      <.button
        id="send-changes"
        type="button"
        variant={:warning}
        phx-click="send-changes"
        phx-disable-with={"Sending to #{@service}…"}
      >
        Send changes
      </.button>
    </.banner>

    <.stat_switch id="chores-switch" label="Chores">
      <:view
        :for={{view, label} <- @views}
        id={"chores-view-#{view}"}
        patch={view_path(@current_team, view)}
        current={@view == view}
        count={Map.fetch!(@counts, view)}
      >
        {label}
      </:view>
    </.stat_switch>

    <%= case @view do %>
      <% :waiting -> %>
        <.empty_state :if={@chores == []} id="no-waiting-chores" title="No chores waiting">
          Chores members log show here for you to accept.
        </.empty_state>

        <div :if={@chores != []}>
          <p class="hint mb-4">
            Clear the box next to a chore to leave it waiting. Open a chore to change or decline it.
          </p>
          <.form for={%{}} id="accept-form" phx-change="select" phx-submit="accept">
            <.chore_table
              id="waiting-chores"
              chores={@chores}
              selected={@selected}
              today={@today}
              current_team={@current_team}
            />
            <.form_actions>
              <.button
                id="accept"
                variant={:success}
                disabled={MapSet.size(@selected) == 0}
                phx-disable-with={"Sending to #{@service}…"}
              >
                Accept {count_chores(MapSet.size(@selected))}
              </.button>
            </.form_actions>
          </.form>
        </div>
      <% :accepted -> %>
        <.empty_state :if={@events == []} id="no-chore-events" title={"Nothing in #{@service} yet"}>
          Chores you accept show here, under their {@service} activity.
        </.empty_state>
        <p :if={@events != []} class="hint">
          Open a chore to change or decline it, which changes its activity. Edits made in {@service} are replaced.
        </p>

        <section :for={row <- @events} id={"chore-event-#{row.event.id}"} class="mt-8">
          <.heading_row>
            <h2 class="subheading">
              {Format.month_year_long(row.event.month)} · {row.event.chore_category.title}
            </h2>
            <:note>
              {Format.count(row.members, one: "1 member", many: "%d members")} · {Format.duration(
                row.minutes
              )}
            </:note>
          </.heading_row>
          <p class="hint mb-4">
            <span :if={row.activity}>
              {@service} activity
              <.a navigate={~p"/teams/#{@current_team}/activities/#{row.activity.id}"}>{row.activity.ref_id}</.a>
            </span>
            <span :if={!row.activity and row.event.d4h_activity_id}>
              {@service} activity linked after the next refresh
            </span>
            <span :if={row.event.sent_at}>
              {if row.event.d4h_activity_id, do: "· "}Sent {Format.date_short(
                row.event.sent_at,
                @current_team.timezone
              )}
            </span>
            <span :if={row.event.send_note} class="block">{row.event.send_note}</span>
            <span :if={row.event.needs_send and !row.event.send_note} class="block">Not sent yet</span>
          </p>
          <.chore_table
            :if={row.chores != []}
            id={"chore-event-#{row.event.id}-chores"}
            chores={row.chores}
            today={@today}
            current_team={@current_team}
            category={false}
          />
        </section>
      <% :declined -> %>
        <.empty_state :if={@chores == []} id="no-declined-chores" title="No chores declined">
          Chores you decline show here, with the reason.
        </.empty_state>
        <.chore_table
          :if={@chores != []}
          id="declined-chores"
          chores={@chores}
          today={@today}
          current_team={@current_team}
        />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :chores, :list, required: true
  attr :selected, :any, default: nil, doc: "the ids checked, or nil for no boxes"
  attr :today, :any, required: true
  attr :current_team, :map, required: true
  attr :category, :boolean, default: true

  # Chores, each linking its page. With `selected`, a box each, for accepting.
  defp chore_table(assigns) do
    ~H"""
    <.table id={@id} rows={@chores} row_id={&"chore-#{&1.id}"} class="table-striped table-stack">
      <:col :let={chore} :if={@selected} label="" class="w-px stack-check" select_all>
        <input
          type="checkbox"
          id={"#{@id}-select-#{chore.id}"}
          name="chore_ids[]"
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
        <span :if={chore.status == :declined} class="hint block">
          {ChoreText.declined(chore, @current_team.timezone)}
        </span>
      </:col>
      <:col :let={chore} :if={@category} label="Category">{chore.chore_category.title}</:col>
      <:col :let={chore} label="Time" class="whitespace-nowrap" align="right">
        {Format.duration(chore.minutes)}
      </:col>
    </.table>
    """
  end

  def handle_event("select", params, socket),
    do: {:noreply, assign(socket, :selected, params |> ids("chore_ids") |> MapSet.new())}

  def handle_event("accept", params, socket) do
    %{current_team: team, current_user: user, service: service} = socket.assigns

    case ids(params, "chore_ids") do
      [] ->
        {:noreply, put_flash(socket, :error, "Select at least 1 chore to accept.")}

      ids ->
        now = DateTime.utc_now()
        count = SaveChore.accept(team, ids, user, now)
        result = SendChores.call(team, user, now)
        {kind, text} = ChoreText.send_flash("Accepted #{count_chores(count)}", result, service)

        socket
        |> put_flash(kind, text)
        |> load()
        |> then(&{:noreply, &1})
    end
  end

  def handle_event("send-changes", _params, socket) do
    %{current_team: team, current_user: user, service: service} = socket.assigns
    result = SendChores.call(team, user, DateTime.utc_now())
    {kind, text} = ChoreText.send_flash(nil, result, service)

    socket
    |> put_flash(kind, text)
    |> load()
    |> then(&{:noreply, &1})
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

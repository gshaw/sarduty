defmodule Web.ChoreCollectionLive do
  use Web, {:live_view_app_layout, access: :team, member_events: ["delete"]}

  import Web.ChoreText, only: [own_box: 1, status_badge: 1]
  import Web.Components.Chart, only: [stat: 1]
  import Web.Components.MemberColumn
  import Web.Components.StatSwitch

  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Operation.SaveChore
  alias App.Operation.SendChores
  alias App.ViewData.MemberChores
  alias Service.Format
  alias Web.ChoreText

  # Chores (#341), /teams/:subdomain/chores: one page for everyone on the team (#645).
  # Anyone who is a member logs chores here and sees their own, Yours, with what a team
  # admin decided; a member changes one only while it waits. Team admins also get the
  # team's chores by status. Waiting chores to accept, with the Review changes pattern:
  # every row starts selected, and a cleared row stays. Accepting sends them to D4H, onto
  # each chore category's activity for the month, and Accepted lists them under those
  # activities. Every chore opens its own page, to change or decline it. A team admin's
  # own chores say Yours and start cleared: another team admin should accept them, and
  # accepting their own takes a box that says they meant it (#697).
  @team_views [waiting: "Waiting", accepted: "Accepted", declined: "Declined"]

  def mount(_params, _session, socket) do
    %{current_team: team, current_member: member, team_admin?: team_admin?} = socket.assigns
    if !Team.chores?(team), do: raise(Web.Status.NotFound)

    views =
      if(team_admin?, do: @team_views, else: []) ++
        if(member, do: [yours: "Yours"], else: [])

    socket
    |> assign(
      page_title: "Chores",
      views: views,
      today: Service.Period.today(DateTime.utc_now(), team.timezone)
    )
    |> then(&{:ok, &1})
  end

  # A team admin opens on Waiting, a member on Yours.
  def handle_params(params, _uri, socket) do
    [{first, _label} | _views] = views = socket.assigns.views
    wanted = params["view"] || Atom.to_string(first)
    view = views |> Keyword.keys() |> Enum.find(&(Atom.to_string(&1) == wanted))
    if !view, do: raise(Web.Status.NotFound)

    socket
    |> assign(view: view)
    |> load()
    |> then(&{:noreply, &1})
  end

  @doc "The Chores page showing chores in `status`, or `:yours`, the member's own."
  def view_path(team, :waiting), do: ~p"/teams/#{team}/chores"
  def view_path(team, view), do: ~p"/teams/#{team}/chores?#{[view: view]}"

  defp load(%{assigns: %{team_admin?: false}} = socket),
    do: socket |> assign(counts: %{}, to_send: 0) |> load_yours()

  defp load(socket) do
    team_id = socket.assigns.current_team.id
    counts = Chore.count_by_status(team_id)

    socket
    |> assign(
      counts: counts,
      to_send: ChoreEvent.count_to_send(team_id),
      chore_count: counts.waiting
    )
    |> load_yours()
    |> load_view(socket.assigns.view, team_id)
    |> assign_standings()
  end

  # The standing of everyone in the view's tables, which only team admins see.
  defp assign_standings(socket) do
    %{current_team: team} = socket.assigns
    events = Map.get(socket.assigns, :events, [])
    chores = Map.get(socket.assigns, :chores, []) ++ Enum.flat_map(events, & &1.chores)
    members = chores |> Enum.map(& &1.member) |> Enum.uniq_by(& &1.id)
    assign(socket, :standings, Standing.by_member(team, members, DateTime.utc_now()))
  end

  # The member's own chores, for the Yours tile's count and its view.
  defp load_yours(%{assigns: %{current_member: nil}} = socket), do: socket

  defp load_yours(socket) do
    %{current_member: member, today: today, counts: counts} = socket.assigns
    chores = Chore.get_all_for_member(member)

    assign(socket,
      counts: Map.put(counts, :yours, length(chores)),
      months: MemberChores.months(chores),
      stats: MemberChores.stats(chores, today.year)
    )
  end

  defp load_view(socket, :yours, _team_id), do: socket

  defp load_view(socket, :waiting, team_id) do
    member = socket.assigns.current_member
    waiting = Chore.get_all_for_team(team_id, :waiting)
    others = Enum.reject(waiting, &Chore.own?(&1, member))
    socket |> assign(chores: waiting, own: false) |> select(MapSet.new(others, & &1.id))
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
    ~H"""
    <.heading_row>
      <h1 class="title">Chores</h1>
      <:action :if={@current_member}>
        <.button id="chore-log" variant={:success} navigate={~p"/teams/#{@current_team}/chores/new"}>
          Log a chore
        </.button>
      </:action>
    </.heading_row>
    <p :if={@team_admin?} class="lead measure">
      Accepting a chore counts it and sends it. Each chore category gets one activity a month.
    </p>
    <p :if={!@team_admin?} class="lead measure">
      Time you give the team outside activities, such as fixing equipment or admin. A team admin accepts each chore before it counts.
    </p>

    <.banner :if={@to_send > 0} kind={:warning} title="Changes not sent" id="chores-to-send">
      <p>
        {Format.count(@to_send,
          one: "1 activity is out of date.",
          many: "%d activities are out of date."
        )}
      </p>
      <.button
        id="send-changes"
        type="button"
        variant={:warning}
        phx-click="send-changes"
        phx-disable-with="Sending…"
      >
        Send changes
      </.button>
    </.banner>

    <.stat_switch :if={length(@views) > 1} id="chores-switch" label="Chores">
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
              standings={@standings}
              selected={@selected}
              today={@today}
              current_team={@current_team}
              current_member={@current_member}
            />
            <div :if={@own_selected?} class="mt-4">
              <.own_box checked={@own} />
            </div>
            <.form_actions>
              <.button
                id="accept"
                variant={:success}
                disabled={MapSet.size(@selected) == 0 or (@own_selected? and !@own)}
                phx-disable-with="Sending…"
              >
                Accept {count_chores(MapSet.size(@selected))}
              </.button>
            </.form_actions>
          </.form>
        </div>
      <% :accepted -> %>
        <.empty_state :if={@events == []} id="no-chore-events" title="Nothing sent yet">
          Chores you accept show here, under their activity.
        </.empty_state>
        <p :if={@events != []} class="hint">
          Open a chore to change or decline it, which changes its activity. Edits made outside SAR Duty are replaced.
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
              Activity
              <.a navigate={~p"/teams/#{@current_team}/activities/#{row.activity.id}"}>{row.activity.ref_id}</.a>
            </span>
            <span :if={!row.activity and row.event.d4h_activity_id}>
              Activity linked after the next refresh
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
            standings={@standings}
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
          standings={@standings}
          today={@today}
          current_team={@current_team}
        />
      <% :yours -> %>
        <.yours
          months={@months}
          stats={@stats}
          today={@today}
          team={@current_team}
          team_admin?={@team_admin?}
        />
    <% end %>
    """
  end

  attr :months, :list, required: true
  attr :stats, :map, required: true
  attr :today, :any, required: true
  attr :team, :map, required: true
  attr :team_admin?, :boolean, required: true

  # The member's own chores by the month they were done, with what a team admin decided.
  # A team admin changes their own from its page, as any chore; a member only while it waits.
  defp yours(assigns) do
    ~H"""
    <.empty_state :if={@months == []} id="no-chores" title="No chores yet">
      Log a chore after you do one. It counts once a team admin accepts it.
    </.empty_state>

    <div :if={@months != []} id="chore-stats" class="chart-stats">
      <.stat
        id="stat-accepted-hours"
        value={Format.duration(@stats.accepted_minutes)}
        label={"Accepted in #{@today.year}"}
      />
      <.stat
        id="stat-accepted-count"
        value={Format.number(@stats.accepted_count)}
        label={"Chores accepted in #{@today.year}"}
      />
      <.stat
        id="stat-waiting"
        value={Format.duration(@stats.waiting_minutes)}
        label="Waiting for a team admin"
      />
    </div>

    <section :for={month <- @months} id={"chores-#{Date.to_iso8601(month.month)}"} class="mt-8">
      <.heading_row>
        <h2 class="subheading">{Format.month_year_long(month.month)}</h2>
        <:note>{ChoreText.summary(month)}</:note>
      </.heading_row>
      <.table
        id={"chores-table-#{Date.to_iso8601(month.month)}"}
        rows={month.chores}
        row_id={&"chore-#{&1.id}"}
        class="table-striped table-stack"
      >
        <:col :let={chore} label="Date" class="w-1/12 whitespace-nowrap">
          {Format.day_in_year(chore.date, @today)}
        </:col>
        <:col :let={chore} label="What you did" class="stack-title">
          <.a :if={@team_admin?} navigate={~p"/teams/#{@team}/chores/#{chore.id}"}>{chore.description}</.a>
          <span :if={!@team_admin?}>{chore.description}</span>
          <span class="hint block">{chore.chore_category.title}</span>
          <span :if={chore.status == :declined} class="hint block mt-1">
            {ChoreText.declined(chore, @team.timezone)}
          </span>
        </:col>
        <:col :let={chore} label="Time" class="w-1/12 whitespace-nowrap" align="right">
          {Format.duration(chore.minutes)}
        </:col>
        <:col :let={chore} label="" class="stack-optional w-px whitespace-nowrap">
          <.status_badge chore={chore} />
          <.a
            :if={!@team_admin? and Chore.member_can_change?(chore)}
            id={"chore-change-#{chore.id}"}
            navigate={~p"/teams/#{@team}/chores/#{chore.id}/edit"}
          >Change</.a>
          <.a
            :if={chore.status == :declined}
            id={"chore-delete-#{chore.id}"}
            href="#"
            phx-click="delete"
            phx-value-id={chore.id}
            data-confirm={"Delete #{chore.description}?"}
          >Delete</.a>
        </:col>
      </.table>
    </section>

    <p :if={@months != [] and !@team_admin?} class="hint mt-4">
      To change an accepted chore, ask a team admin.
    </p>
    """
  end

  attr :id, :string, required: true
  attr :chores, :list, required: true
  attr :standings, :map, required: true
  attr :selected, :any, default: nil, doc: "the ids checked, or nil for no boxes"
  attr :today, :any, required: true
  attr :current_team, :map, required: true
  attr :category, :boolean, default: true
  attr :current_member, :map, default: nil

  # Chores, each linking its page. With `selected`, a box each, for accepting. Select all
  # passes over the team admin's own.
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
          data-select-all={Chore.own?(chore, @current_member) && "skip"}
        />
      </:col>
      <:col :let={chore} label="Member" class="stack-title">
        <.member_cell
          member={chore.member}
          team={@current_team}
          standing={@standings[chore.member.id]}
        />
        <.badge
          :if={Chore.own?(chore, @current_member)}
          id={"chore-yours-#{chore.id}"}
          kind={:primary}
        >
          Yours
        </.badge>
      </:col>
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

  def handle_event("select", params, socket) do
    socket
    |> assign(:own, params["own"] == "true")
    |> select(params |> ids("chore_ids") |> MapSet.new())
    |> then(&{:noreply, &1})
  end

  def handle_event("accept", params, socket) do
    %{current_team: team, current_user: user, current_member: member} = socket.assigns
    now = DateTime.utc_now()

    with [_id | _ids] = ids <- ids(params, "chore_ids"),
         {:ok, count} <-
           SaveChore.accept(team, ids, user, now, member: member, own: params["own"] == "true") do
      result = SendChores.call(team, user, now)
      {kind, text} = ChoreText.send_flash("Accepted #{count_chores(count)}", result)

      socket
      |> put_flash(kind, text)
      |> load()
      |> then(&{:noreply, &1})
    else
      [] -> {:noreply, put_flash(socket, :error, "Select at least 1 chore to accept.")}
      {:error, :own} -> {:noreply, put_flash(socket, :error, ChoreText.own_refused())}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    member = socket.assigns.current_member
    chore = Chore.find_for_member!(member, id)

    socket =
      case SaveChore.delete_own(member, chore) do
        :ok ->
          put_flash(socket, :info, "Deleted #{chore.description}.")

        {:error, :decided} ->
          put_flash(socket, :error, "This chore cannot be deleted. A team admin has accepted it.")
      end

    {:noreply, load(socket)}
  end

  def handle_event("send-changes", _params, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    result = SendChores.call(team, user, DateTime.utc_now())
    {kind, text} = ChoreText.send_flash(nil, result)

    socket
    |> put_flash(kind, text)
    |> load()
    |> then(&{:noreply, &1})
  end

  # The rows checked, and whether any is the team admin's own, which shows the box.
  defp select(socket, selected) do
    %{chores: chores, current_member: member} = socket.assigns

    own_selected? =
      Enum.any?(chores, &(Chore.own?(&1, member) and MapSet.member?(selected, &1.id)))

    assign(socket, selected: selected, own_selected?: own_selected?)
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

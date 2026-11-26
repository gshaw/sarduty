defmodule Web.ChoreCollectionLive do
  use Web, {:live_view_app_layout, access: :team, member_events: ["delete"]}

  import Web.ChoreText, only: [own_box: 1, status_badge: 1]
  import Web.Components.Chart, only: [stat: 1]
  import Web.Components.FilterBar
  import Web.Components.StatSwitch

  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
  alias App.Model.Member
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Operation.SaveChore
  alias App.Operation.SendChores
  alias App.ViewData.MemberChores
  alias App.ViewData.WaitingChores
  alias App.ViewModel.ChoreFilterViewModel
  alias Service.Format
  alias Web.ChoreText

  # Chores (#341), /teams/:subdomain/chores: one page for everyone on the team (#645).
  # Anyone who is a member logs chores here and sees their own, Yours, with what a team
  # admin decided; a member changes one only while it waits. Team admins also get the
  # team's chores by status. Waiting chores to accept, with the Review changes pattern:
  # every row starts selected, and a cleared row stays. Accepting sends them to D4H, onto
  # each chore category's activity for the month, and Accepted lists them under those
  # activities. Every chore opens its own page, to change or decline it. A team admin's
  # own chores start cleared: another team admin should accept them, and accepting their
  # own takes a box that says they meant it (#697). Chores logged together wait as one
  # row, and accepting it accepts them all (#1102). Team admins filter the three by
  # category and member, and Accepted and Declined by period too (#1116): each tile counts
  # its view with the filters on, and Accept takes only the rows shown.
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

  # A team admin opens on Waiting, a member on Yours. Waiting has no period, so it ignores
  # `when`. Another team's category or member is not found.
  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    view = view!(socket.assigns.views, params["view"])
    {filter_options, changeset} = filter_options!(params, view)
    categories = if socket.assigns.team_admin?, do: ChoreCategory.get_all(team.id), else: []
    picked = picked!(team, categories, filter_options)

    socket
    |> assign(
      view: view,
      filter_options: filter_options,
      form: to_form(changeset, as: "form"),
      categories: categories,
      picked: picked
    )
    |> load()
    |> then(&{:noreply, &1})
  end

  # The member picked, nil for All. Another team's category or member is not found.
  defp picked!(team, categories, %{category: category, member: member}) do
    if category && !Enum.any?(categories, &(&1.id == category)), do: raise(Web.Status.NotFound)
    picked = member && Member.find(team, member)
    if member && !picked, do: raise(Web.Status.NotFound)
    picked
  end

  defp view!([{first, _label} | _rest] = views, wanted) do
    wanted = wanted || Atom.to_string(first)

    views |> Keyword.keys() |> Enum.find(&(Atom.to_string(&1) == wanted)) ||
      raise Web.Status.NotFound
  end

  defp filter_options!(params, view) do
    case ChoreFilterViewModel.validate(params) do
      {:ok, filter_options, changeset} when view == :waiting ->
        {%{filter_options | when: ChoreFilterViewModel.default_when()}, changeset}

      {:ok, filter_options, changeset} ->
        {filter_options, changeset}

      {:error, _changeset} ->
        raise Web.Status.NotFound
    end
  end

  @doc """
  The Chores page showing chores in `status`, or `:yours`, the member's own, with
  `filter_options` from `ChoreFilterViewModel` (#1116).
  """
  def view_path(team, view, filter_options \\ %ChoreFilterViewModel{}) do
    case ChoreFilterViewModel.query_params(view, filter_options) do
      [] -> ~p"/teams/#{team}/chores"
      params -> ~p"/teams/#{team}/chores?#{params}"
    end
  end

  @doc """
  Where a team admin goes after deciding or changing `chore` on its page: the view it's in
  now, on its year when the last 12 months leave it out (#1116).
  """
  def decided_path(team, chore, now) do
    year =
      chore.status != :waiting && ChoreFilterViewModel.when_for(chore.date, now, team.timezone)

    filter_options = if year, do: %ChoreFilterViewModel{when: year}, else: %ChoreFilterViewModel{}
    view_path(team, chore.status, filter_options)
  end

  defp load(%{assigns: %{team_admin?: false}} = socket),
    do: socket |> assign(counts: %{}, to_send: 0) |> load_yours()

  defp load(socket) do
    %{current_team: team, filter_options: filter_options} = socket.assigns
    filter = %{category: filter_options.category, member: filter_options.member}
    dates = ChoreFilterViewModel.dates(filter_options.when, DateTime.utc_now(), team.timezone)
    decided = Map.put(filter, :dates, dates)
    waiting = team.id |> Chore.get_all_for_team(:waiting) |> WaitingChores.rows()
    rows = WaitingChores.filter(waiting, filter)

    socket
    |> assign(
      counts: counts(team.id, rows, decided),
      totals: Chore.count_by_status(team.id),
      to_send: ChoreEvent.count_to_send(team.id),
      filter: filter,
      decided: decided
    )
    |> load_yours()
    |> load_view(socket.assigns.view, team.id, {waiting, rows})
    |> assign_standings()
  end

  # Each tile counts its view with the filters on. Waiting's counts the chores on its rows.
  defp counts(team_id, rows, decided) do
    %{
      waiting: rows |> Enum.map(&length(&1.chores)) |> Enum.sum(),
      accepted: Chore.count_for_team(team_id, :accepted, decided),
      declined: Chore.count_for_team(team_id, :declined, decided)
    }
  end

  # Who has a chore in the view, for Member, and the member picked even with none.
  defp assign_members(socket, members) do
    picked = socket.assigns.picked

    members =
      if picked && !Enum.any?(members, &(&1.id == picked.id)),
        do: Enum.sort_by([picked | members], &{String.downcase(&1.name), &1.id}),
        else: members

    assign(socket, member_options: Enum.map(members, &{&1.name, Integer.to_string(&1.id)}))
  end

  # The year picked stays an option with no chores left in it, as Member keeps its member.
  defp assign_years(socket, team_id) do
    years =
      case Integer.parse(socket.assigns.filter_options.when) do
        {year, ""} -> [year | Chore.years(team_id)] |> Enum.uniq() |> Enum.sort(:desc)
        _other -> Chore.years(team_id)
      end

    assign(socket, when_options: ChoreFilterViewModel.when_kinds(years))
  end

  # The standing of everyone in the view's tables, which only team admins see.
  defp assign_standings(socket) do
    %{current_team: team} = socket.assigns
    events = Map.get(socket.assigns, :events, [])
    rows = Map.get(socket.assigns, :rows, [])

    chores =
      Map.get(socket.assigns, :chores, []) ++
        Enum.flat_map(events, & &1.chores) ++ Enum.flat_map(rows, & &1.chores)

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

  defp load_view(socket, :yours, _team_id, _waiting), do: socket

  # Every row shown starts checked but the reader's own, and the box starts cleared, so a
  # filter that changes starts over.
  defp load_view(socket, :waiting, _team_id, {waiting, rows}) do
    member = socket.assigns.current_member
    others = Enum.reject(rows, &own_row?(&1, member))

    socket
    |> assign(chores: [], rows: rows, own: false)
    |> assign_members(WaitingChores.members(waiting, socket.assigns.filter))
    |> select(MapSet.new(others, & &1.id))
  end

  # Only the activities with a chore that matches, each with those chores. An activity's
  # totals stay whole.
  defp load_view(socket, :accepted, team_id, _waiting) do
    decided = socket.assigns.decided

    by_event =
      team_id |> Chore.get_all_for_team(:accepted, decided) |> Enum.group_by(& &1.chore_event_id)

    events =
      for row <- ChoreEvent.get_all_with_totals(team_id),
          chores = Map.get(by_event, row.event.id),
          do: Map.put(row, :chores, chores)

    socket
    |> assign(events: events)
    |> assign_members(Chore.members_for_team(team_id, :accepted, %{decided | member: nil}))
    |> assign_years(team_id)
  end

  defp load_view(socket, :declined, team_id, _waiting) do
    decided = socket.assigns.decided

    socket
    |> assign(chores: Chore.get_all_for_team(team_id, :declined, decided))
    |> assign_members(Chore.members_for_team(team_id, :declined, %{decided | member: nil}))
    |> assign_years(team_id)
  end

  # Every chore in a row is the reader's own or none is: own?/2 reads the chores logged
  # together, which they share.
  defp own_row?(row, member), do: Enum.any?(row.chores, &Chore.own?(&1, member))

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
        phx-click="send-changes"
        data-confirm={send_changes_confirm(@to_send)}
        data-confirm-button="Send changes"
        phx-disable-with="Sending…"
      >
        Send changes
      </.button>
    </.banner>

    <.stat_switch :if={length(@views) > 1} id="chores-switch" label="Chores">
      <:view
        :for={{view, label} <- @views}
        id={"chores-view-#{view}"}
        patch={view_path(@current_team, view, @filter_options)}
        current={@view == view}
        count={Map.fetch!(@counts, view)}
      >
        {label}
      </:view>
    </.stat_switch>

    <.filter_bar
      :if={@team_admin? and @view != :yours}
      for={@form}
      id="chore_filter_form"
      count={count_chores(Map.fetch!(@counts, @view))}
      repeats
      clear={view_path(@current_team, @view)}
      path_fn={&filter_path(@current_team, @view, @filter_options, &1)}
    >
      <:filter
        field={@form[:category]}
        label="Category"
        options={[{"All", ""} | Enum.map(@categories, &{&1.title, &1.id})]}
        default=""
      />
      <:filter
        field={@form[:member]}
        label="Member"
        type="combobox"
        options={@member_options}
        default=""
      />
      <:filter
        :if={@view != :waiting}
        field={@form[:when]}
        label="Period"
        options={@when_options}
        default={ChoreFilterViewModel.default_when()}
      />
    </.filter_bar>

    <%= case @view do %>
      <% :waiting -> %>
        <.no_match :if={@rows == [] and @totals.waiting > 0} period={false} />
        <.empty_state
          :if={@rows == [] and @totals.waiting == 0}
          id="no-waiting-chores"
          title="No chores waiting"
        >
          Chores members log show here for you to accept.
        </.empty_state>

        <div :if={@rows != []}>
          <p class="hint mb-4">
            Uncheck a chore to leave it waiting. Open a chore to change or decline it.
          </p>
          <.form for={%{}} id="accept-form" phx-change="select" phx-submit="accept">
            <.waiting_table
              id="waiting-chores"
              rows={@rows}
              standings={@standings}
              selected={@selected}
              current_team={@current_team}
              current_member={@current_member}
              picked={@picked}
            />
            <div :if={@own_selected?} class="mt-4">
              <.own_box checked={@own} />
            </div>
            <.form_actions>
              <.button
                id="accept"
                variant={:success}
                disabled={@selected_count == 0 or (@own_selected? and !@own)}
                phx-disable-with="Sending…"
              >
                Accept {count_chores(@selected_count)}
              </.button>
            </.form_actions>
          </.form>
        </div>
      <% :accepted -> %>
        <.no_match :if={@events == [] and @totals.accepted > 0} period />
        <.empty_state
          :if={@events == [] and @totals.accepted == 0}
          id="no-chore-events"
          title="Nothing sent yet"
        >
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
              Activity total: {Format.count(row.members, one: "1 member", many: "%d members")} · {Format.duration(
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
            current_team={@current_team}
            current_member={@current_member}
            category={false}
          />
        </section>
      <% :declined -> %>
        <.no_match :if={@chores == [] and @totals.declined > 0} period />
        <.empty_state
          :if={@chores == [] and @totals.declined == 0}
          id="no-declined-chores"
          title="No chores declined"
        >
          Chores you decline show here, with the reason.
        </.empty_state>
        <.chore_table
          :if={@chores != []}
          id="declined-chores"
          chores={@chores}
          standings={@standings}
          current_team={@current_team}
          current_member={@current_member}
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

  attr :period, :boolean, required: true

  defp no_match(assigns) do
    ~H"""
    <.empty_state id="no-matching-chores" title="No chores match">
      {if @period,
        do: "Change the filters, or select All under Period.",
        else: "Change the filters."}
    </.empty_state>
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
        <:col :let={chore} label="Date" class="w-px whitespace-nowrap">
          <.date_cell value={chore.date} timezone={@team.timezone} />
        </:col>
        <:col :let={chore} label="What you did" class="stack-title">
          <.a :if={@team_admin?} navigate={~p"/teams/#{@team}/chores/#{chore.id}"}>{chore.description}</.a>
          <span :if={!@team_admin?}>{chore.description}</span>
          <span class="hint block">{ChoreText.category_line(chore)}</span>
          <span :if={chore.status == :declined} class="hint block mt-1">
            {ChoreText.declined(chore, @team.timezone)}
          </span>
        </:col>
        <:col :let={chore} label="Hours" class="w-px whitespace-nowrap" align="right">
          <.hours_cell minutes={chore.minutes} />
        </:col>
        <:col :let={chore} label="" class="stack-optional w-px whitespace-nowrap">
          <.status_badge chore={chore} />
          <.a
            :if={!@team_admin? and Chore.member_can_change?(chore)}
            id={"chore-change-#{chore.id}"}
            navigate={~p"/teams/#{@team}/chores/#{chore.id}/edit"}
          >Change</.a>
          <.a
            :if={chore.status == :declined and (!@team_admin? or Chore.team_admin_can_delete?(chore))}
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
  attr :rows, :list, required: true, doc: "from WaitingChores.rows/1"
  attr :standings, :map, required: true
  attr :selected, :any, required: true, doc: "the rows checked, by their first chore's id"
  attr :current_team, :map, required: true
  attr :current_member, :map, default: nil
  attr :picked, :map, default: nil, doc: "the member Member picks, in bold"

  defp waiting_table(assigns) do
    ~H"""
    <.table id={@id} rows={@rows} row_id={&"chore-#{&1.id}"} class="table-striped table-stack">
      <:col :let={row} label="" class="w-px stack-check" select_all>
        <input
          type="checkbox"
          id={"#{@id}-select-#{row.id}"}
          name="chore_ids[]"
          value={row.id}
          checked={MapSet.member?(@selected, row.id)}
          aria-label={"Select #{row.first.description}"}
          data-select-all={own_row?(row, @current_member) && "skip"}
        />
      </:col>
      <:col :let={row} label="Member" class="stack-title">
        <%!-- Each name keeps its badge and comma on its line, and the names wrap between
        them. --%>
        <span class="flex flex-wrap gap-x-1">
          <span
            :for={{chore, i} <- Enum.with_index(row.chores)}
            id={"chore-#{chore.id}-name"}
            class={[
              "whitespace-nowrap",
              @picked && length(row.chores) > 1 && chore.member.id == @picked.id && "font-semibold"
            ]}
          ><.member_cell
            member={chore.member}
            team={@current_team}
            standing={@standings[chore.member.id]}
            id={"chore-#{chore.id}-member"}
            you={you?(chore.member, @current_member)}
          />{if i < length(row.chores) - 1, do: ","}</span>
        </span>
        <span :for={line <- row.differs} class="hint block">{line}</span>
      </:col>
      <:col :let={row} label="Date" class="w-px whitespace-nowrap">
        <.date_cell value={row.first.date} timezone={@current_team.timezone} />
        <span :if={note = logged_note(row.first, @current_team.timezone)} class="hint block">
          {note}
        </span>
      </:col>
      <:col :let={row} label="What they did" class="stack-full">
        <.a navigate={~p"/teams/#{@current_team}/chores/#{row.first.id}"}>{row.first.description}</.a>
      </:col>
      <:col :let={row} label="Category">{row.first.chore_category.title}</:col>
      <:col :let={row} label="Hours" class="w-px whitespace-nowrap" align="right">
        <span :if={row.minutes_each} id={"chore-#{row.id}-each"}>
          <.hours_cell minutes={row.minutes_each} /> each
        </span>
        <span :if={row.minutes_each} class="hint block"><.hours_cell minutes={row.minutes} /></span>
        <.hours_cell :if={!row.minutes_each} minutes={row.minutes} />
      </:col>
    </.table>
    """
  end

  defp you?(member, current_member), do: current_member != nil and member.id == current_member.id

  attr :id, :string, required: true
  attr :chores, :list, required: true
  attr :standings, :map, required: true
  attr :current_team, :map, required: true
  attr :category, :boolean, default: true
  attr :current_member, :map, default: nil

  defp chore_table(assigns) do
    ~H"""
    <.table id={@id} rows={@chores} row_id={&"chore-#{&1.id}"} class="table-striped table-stack">
      <:col :let={chore} label="Member" class="stack-title">
        <.member_cell
          member={chore.member}
          team={@current_team}
          standing={@standings[chore.member.id]}
          id={"chore-#{chore.id}-member"}
          you={you?(chore.member, @current_member)}
        />
      </:col>
      <:col :let={chore} label="Date" class="w-px whitespace-nowrap">
        <.date_cell value={chore.date} timezone={@current_team.timezone} />
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
      <:col :let={chore} label="Hours" class="w-px whitespace-nowrap" align="right">
        <.hours_cell minutes={chore.minutes} />
      </:col>
    </.table>
    """
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    case ChoreFilterViewModel.validate(form_params) do
      # Enter in a closed combobox submits the same filters; a patch would recheck every row.
      {:ok, filter_options, _changeset} when filter_options == socket.assigns.filter_options ->
        {:noreply, socket}

      {:ok, filter_options, _changeset} ->
        %{current_team: team, view: view} = socket.assigns
        {:noreply, push_patch(socket, to: view_path(team, view, filter_options), replace: true)}

      {:error, _changeset} ->
        raise Web.Status.NotFound
    end
  end

  def handle_event("select", params, socket) do
    socket
    |> assign(:own, params["own"] == "true")
    |> select(params |> ids("chore_ids") |> MapSet.new())
    |> then(&{:noreply, &1})
  end

  def handle_event("accept", params, socket) do
    %{current_team: team, current_user: user, current_member: member, filter: filter} =
      socket.assigns

    now = DateTime.utc_now()
    opts = [member: member, own: params["own"] == "true", filter: filter]

    with [_id | _ids] = ids <- params |> ids("chore_ids") |> row_ids(socket.assigns),
         {:ok, count} <- SaveChore.accept(team, ids, user, now, opts) do
      {kind, text} =
        ChoreText.send_flash("Accepted #{count_chores(count)}", SendChores.call(team, user, now))

      {:noreply, socket |> put_flash(kind, text) |> load()}
    else
      [] -> {:noreply, put_flash(socket, :error, "Select at least 1 chore to accept.")}
      {:error, :own} -> {:noreply, put_flash(socket, :error, ChoreText.own_refused())}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    %{current_member: member, team_admin?: team_admin?} = socket.assigns
    chore = Chore.find_for_member!(member, id)

    socket =
      case SaveChore.delete_own(member, chore, if(team_admin?, do: :team_admin, else: :member)) do
        :ok ->
          put_flash(socket, :info, "Deleted #{chore.description}.")

        {:error, :decided} ->
          put_flash(socket, :error, "This chore cannot be deleted. A team admin has accepted it.")

        {:error, :others_wait} ->
          put_flash(
            socket,
            :error,
            "This chore cannot be deleted while a chore logged with it waits."
          )
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

  defp select(socket, selected) do
    %{rows: rows, current_member: member} = socket.assigns
    checked = Enum.filter(rows, &MapSet.member?(selected, &1.id))

    assign(socket,
      selected: MapSet.new(checked, & &1.id),
      selected_count: checked |> Enum.map(&length(&1.chores)) |> Enum.sum(),
      own_selected?: Enum.any?(checked, &own_row?(&1, member))
    )
  end

  # A row's box sends its first chore's id, which a member may have deleted since the
  # page loaded, so each checked row sends every chore it had.
  defp row_ids(ids, %{rows: rows}) do
    Enum.flat_map(ids, fn id -> Enum.find_value(rows, [id], &(&1.id == id && &1.ids)) end)
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

  # A chip's path, with the filter it removes back at its default.
  defp filter_path(team, view, filter_options, changed) do
    changed =
      Map.new(changed, fn {key, value} -> {key, if(value == "", do: nil, else: value)} end)

    view_path(team, view, Map.merge(filter_options, changed))
  end

  defp count_chores(n), do: Format.count(n, one: "%d chore", many: "%d chores")

  # Send changes asks first and says what it changes, as no button is yellow (#995).
  defp send_changes_confirm(count) do
    Format.count(count,
      one: "Send changes to 1 activity? It gets the chores accepted for its category and month.",
      many:
        "Send changes to %d activities? Each gets the chores accepted for its category and month."
    )
  end
end

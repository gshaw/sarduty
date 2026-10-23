defmodule Web.TeamDashboardLive do
  use Web, {:live_view_app_layout, access: :team}

  import Web.Components.ActivityMap
  import Web.Components.Chart
  import Web.Components.OpenInMaps

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Chore
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.ViewData.MemberRecords
  alias App.ViewData.MemberToDo
  alias App.ViewData.TeamDashboardCharts
  alias App.ViewData.TeamDashboardViewData
  alias App.Worker.RefreshTeamDataWorker
  alias App.Worker.SyncTeamChangesWorker
  alias Service.Format
  alias Web.Components.ActivityMap

  # The top half is what needs doing: what's next, and what needs a team admin. The lower
  # half is the team's year, loaded after it so the work never waits on the charts (#205).
  #
  # Members open it too (#406), read only, and see what a team admin sees: Next up,
  # Coming up, and the team's year, plus For you to do. Team admins also get Take
  # attendance, Needs attention, and Refresh now. A team admin who is a member gets both
  # lists.

  def mount(_params, _session, socket) do
    current_team = socket.assigns.current_team

    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")
      # Opening the dashboard catches up with D4H rather than waiting for the next sync.
      if socket.assigns.team_admin?,
        do: SyncTeamChangesWorker.enqueue_if_stale(current_team, DateTime.utc_now())
    end

    socket =
      socket
      |> assign(page_title: current_team.name)
      |> assign_page(current_team)

    {:ok, socket}
  end

  defp assign_page(socket, team), do: socket |> assign_top_half(team) |> assign_pulse(team)

  defp assign_top_half(socket, team) do
    now = DateTime.utc_now()

    socket
    |> assign(now: now)
    |> assign(
      view_data: TeamDashboardViewData.build(team, now, attention?: socket.assigns.team_admin?)
    )
    |> assign(has_logo: Team.logo_file(team.subdomain) != nil)
    |> assign_member(now)
  end

  # What a member has to do, from Your membership's records.
  defp assign_member(%{assigns: %{current_member: nil}} = socket, _now),
    do: assign(socket, to_do: [])

  defp assign_member(%{assigns: %{current_member: member}} = socket, now) do
    # Only a team with ID cards on offers one, as Your membership does.
    card = if member.team.id_cards_enabled, do: MemberCard.find_current(member.team, member)
    in_wallet? = card != nil and MemberCard.in_wallet?(card)
    letters = TaxCreditLetter.get_all_for_member(member)
    qualifications = MemberRecords.qualifications(member, now)

    chores =
      if member.team.member_logins,
        do: Chore.get_all_for_member(member, status: :declined),
        else: []

    assign(socket,
      to_do:
        MemberToDo.items(
          card,
          in_wallet?,
          letters,
          qualifications,
          now,
          member.team.timezone,
          chores
        )
    )
  end

  defp assign_pulse(socket, team) do
    assign_async(socket, :pulse, fn -> {:ok, %{pulse: build_pulse(team)}} end, reset: false)
  end

  defp build_pulse(team) do
    charts = team |> TeamDashboardViewData.chart_rows() |> TeamDashboardCharts.shape(team)
    %{charts: charts, map: ActivityMap.build(charts.map_points, {520, 380}, padding: 24)}
  end

  def render(assigns) do
    ~H"""
    <div class="heading-row team-heading">
      <div class="min-w-0">
        <h1 class="title-hero mb-0">{@current_team.name}</h1>
        <.refresh_line
          team={@current_team}
          view_data={@view_data}
          now={@now}
          team_admin?={@team_admin?}
        />
      </div>
      <img
        :if={@has_logo}
        id="team-logo"
        src={~p"/teams/#{@current_team}/logo?shape=square"}
        class="logo-lg"
        alt="Team logo"
      />
    </div>

    <.next_up
      :if={@view_data.next_up}
      team={@current_team}
      activity={@view_data.next_up}
      maps_app={@current_user.maps_app}
      now={@now}
      team_admin?={@team_admin?}
    />

    <div class="card-grid">
      <.coming_up
        team={@current_team}
        activities={@view_data.coming_up}
        now={@now}
        team_admin?={@team_admin?}
      />
      <div class="card-stack span-6">
        <.needs_attention :if={@team_admin?} team={@current_team} items={@view_data.attention} />
        <.to_do :if={@current_member} team={@current_team} items={@to_do} />
      </div>
    </div>

    <.async_result :let={pulse} assign={@pulse}>
      <:loading>
        <p id="pulse-loading" class="chart-caption">Drawing the charts…</p>
      </:loading>
      <:failed>
        <p id="pulse-failed" class="chart-caption">
          The charts cannot load. Reload the page.
        </p>
      </:failed>
      <.pulse
        team={@current_team}
        charts={pulse.charts}
        map={pulse.map}
        team_admin?={@team_admin?}
      />
    </.async_result>
    """
  end

  attr :team, :map, required: true
  attr :view_data, :map, required: true
  attr :now, :any, required: true
  attr :team_admin?, :boolean, required: true

  # Two lines that keep their size while a refresh runs, so nothing under them moves: what
  # SAR Duty last did, cut to one line, then the links, which stay put. Refresh now is
  # disabled while a refresh runs rather than hidden. Only team admins refresh; everyone
  # gets Open D4H.
  defp refresh_line(assigns) do
    assigns = assign(assigns, :refreshing?, refreshing?(assigns.view_data))

    ~H"""
    <div class="hint mt-1">
      <p id="refresh-status" class="mb-0 truncate">
        <.spinner :if={@refreshing?} id="refreshing" class="text-link">
          {refreshing_text(@team, @view_data.refresh_result)}
        </.spinner>
        <span :if={!@refreshing?} id="d4h-updated">{refreshed_ago(@team, @now)}</span>
      </p>
      <p :if={@team_admin? or !D4H.records?(@team)} class="mb-0 flex items-center gap-3">
        <.button
          :if={@team_admin?}
          id="refresh-now"
          type="button"
          variant={:link}
          size={:sm}
          phx-click="refresh"
          disabled={@refreshing?}
        >
          Refresh now
        </.button>
        <span :if={@team_admin? and !D4H.records?(@team)} aria-hidden="true">·</span>
        <.a :if={!D4H.records?(@team)} external={true} href={D4H.build_url(@team, "/dashboard")}>
          Open D4H
        </.a>
      </p>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :activity, :map, required: true
  attr :maps_app, :string, required: true
  attr :now, :any, required: true
  attr :team_admin?, :boolean, required: true

  # The team's next activity, the same card for everyone. Team admins also take
  # attendance from it.
  defp next_up(assigns) do
    ~H"""
    <section id="next-up" class="card next-up">
      <div class="next-up-when">
        <span class="hint">Next up</span>
        <span class="next-up-day">
          {Format.day_coming_up(@activity.started_at, @now, @team.timezone)}
        </span>
        <span class="next-up-time">{Format.time_short(@activity.started_at, @team.timezone)}</span>
      </div>
      <div class="min-w-0">
        <.activity_kind_mark activity={@activity} class="text-sm" />
        <h2 class="next-up-title">
          <.a navigate={~p"/teams/#{@team}/activities/#{@activity.id}"}>{@activity.title}</.a>
        </h2>
        <p class="hint">{where_and_when(@activity, @now)}</p>
        <.open_in_maps
          id="next-up-maps"
          app={@maps_app}
          coordinate={Activity.pin(@activity)}
          address={@activity.address}
          label={@activity.title}
        />
      </div>
      <.button
        :if={@team_admin?}
        id="next-up-take-attendance"
        variant={:primary}
        navigate={~p"/teams/#{@team}/activities/#{@activity.id}/take-attendance"}
      >
        Take attendance
      </.button>
    </section>
    """
  end

  # "Murrin Park · in 3 hours", or the time alone when D4H has no place.
  defp where_and_when(activity, now) do
    [activity.address, Format.starts_in(activity.started_at, now)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  attr :team, :map, required: true
  attr :activities, :list, required: true
  attr :now, :any, required: true
  attr :team_admin?, :boolean, required: true

  defp coming_up(assigns) do
    ~H"""
    <section id="coming-up" class="card span-6">
      <header>
        <h2 class="chart-title">Coming up</h2>
        <span class="hint">Next 14 days</span>
      </header>
      <p :if={@activities == []} id="coming-up-empty" class="chart-caption">
        No activities planned in {D4H.service_name(@team)}.
      </p>
      <ul :if={@activities != []} id="coming-up-list" class="row-links">
        <li :for={activity <- @activities} id={"coming-up-#{activity.id}"}>
          <.row_link navigate={~p"/teams/#{@team}/activities/#{activity.id}"}>
            <.coming_up_row team={@team} activity={activity} now={@now} />
          </.row_link>
        </li>
      </ul>
      <footer class="action">
        <.a navigate={~p"/teams/#{@team}/activities?when=future&sort=date"}>
          All future activities
        </.a>
      </footer>
    </section>
    """
  end

  attr :team, :map, required: true
  attr :activity, :map, required: true
  attr :now, :any, required: true

  defp coming_up_row(assigns) do
    ~H"""
    <span class="dash-row">
      <span class="dash-row-when">
        <strong>{Format.day_coming_up(@activity.started_at, @now, @team.timezone)}</strong>
        <span class="text-text-muted">
          {Format.time_short(@activity.started_at, @team.timezone)}
        </span>
      </span>
      <span class="dash-row-title">
        <.activity_kind_mark activity={@activity} class="text-sm" />
        <span class="text-link">{@activity.title}</span>
      </span>
    </span>
    """
  end

  attr :team, :map, required: true
  attr :items, :list, required: true

  defp needs_attention(assigns) do
    ~H"""
    <section id="needs-attention" class="card">
      <header>
        <h2 class="chart-title">Needs attention</h2>
      </header>
      <p :if={@items == []} id="needs-attention-empty" class="chart-caption">
        Nothing needs you right now.
      </p>
      <ul :if={@items != []} id="needs-attention-list" class="row-links attention">
        <li :for={item <- @items} id={"attention-#{item.key}"} class={"is-#{item.level}"}>
          <.row_link navigate={attention_path(@team, item)}>
            <span class="dash-row">
              <span class="attention-mark" aria-hidden="true"></span>
              <span class="dash-row-title">
                <strong class="text-link">{item.title}</strong>
                <span :if={item.detail} class="hint">{item.detail}</span>
              </span>
            </span>
          </.row_link>
        </li>
      </ul>
    </section>
    """
  end

  defp attention_path(team, %{key: :refresh}), do: ~p"/teams/#{team}/settings"

  defp attention_path(team, %{key: key, year: year}) when key in [:untagged, :untagged_last_year],
    do: ~p"/teams/#{team}/activities?hours=untagged&status=published&when=#{year}&sort=date-"

  defp attention_path(team, %{key: :drafts}),
    do: ~p"/teams/#{team}/activities?status=draft&when=recent&sort=date-"

  defp attention_path(team, %{key: :expiring}),
    do: ~p"/teams/#{team}/qualifications?view=expiring"

  defp attention_path(team, %{key: :missing_details}),
    do: ~p"/teams/#{team}/members?details=missing"

  # The item's own filters, from the team's attendance check (#366).
  defp attention_path(team, %{key: :not_seen, params: params}),
    do: ~p"/teams/#{team}/members?#{params}"

  defp attention_path(team, %{key: :watch_missing}), do: ~p"/teams/#{team}/settings"

  defp attention_path(team, %{key: :group_changes}), do: ~p"/teams/#{team}/groups"

  defp attention_path(team, %{key: :proposed_changes}),
    do: ~p"/teams/#{team}/proposed-changes"

  defp attention_path(team, %{key: key}) when key in [:chores, :chores_to_send],
    do: ~p"/teams/#{team}/chores"

  defp attention_path(team, %{key: :letters, year: year}),
    do: ~p"/teams/#{team}/tax-credit-letters?year=#{year}"

  attr :team, :map, required: true
  attr :items, :list, required: true

  # What a member has to do (#389), moved here from their old overview (#406).
  defp to_do(assigns) do
    ~H"""
    <section id="to-do" class="card">
      <header>
        <h2 class="chart-title">For you to do</h2>
      </header>
      <p :if={@items == []} id="to-do-empty" class="chart-caption">Nothing to do right now.</p>
      <ul :if={@items != []} id="to-do-list" class="divide-y divide-border-subtle">
        <.to_do_item :for={item <- @items} team={@team} item={item} />
      </ul>
      <p :if={@items != []} class="hint mt-2 mb-0">Each one leaves this list once it's done.</p>
    </section>
    """
  end

  attr :team, :map, required: true
  attr :item, :map, required: true

  defp to_do_item(%{item: %{key: :card}} = assigns) do
    ~H"""
    <li id="to-do-card" class="py-3">
      <strong class="block">Add your ID card to Wallet</strong>
      <span class="hint block">Show it at the door. Anyone can verify it.</span>
      <%!-- Under the text: two Wallet buttons beside it squeeze it to a narrow column. --%>
      <div class="flex flex-wrap gap-2 mt-2">
        <.button
          :if={BuildApplePass.configured?()}
          id="to-do-apple-pass"
          href={~p"/teams/#{@team}/me/card/apple-wallet"}
        >
          Add to Apple Wallet
        </.button>
        <.button
          :if={BuildGooglePass.configured?()}
          id="to-do-google-pass"
          href={~p"/teams/#{@team}/me/card/google-wallet"}
        >
          Add to Google Wallet
        </.button>
      </div>
    </li>
    """
  end

  defp to_do_item(%{item: %{key: :qualification}} = assigns) do
    ~H"""
    <li id={"to-do-qualification-#{@item.award.qualification_id}"} class="py-3">
      <.a navigate={~p"/teams/#{@team}/me"} class="font-semibold">
        Your {@item.award.qualification.title} expires in {Format.days(@item.days)}
      </.a>
      <span class="hint block">Renewed it? Give the new certificate to a team admin.</span>
    </li>
    """
  end

  defp to_do_item(%{item: %{key: :declined_chores}} = assigns) do
    ~H"""
    <li id="to-do-declined-chores" class="py-3">
      <.a navigate={~p"/teams/#{@team}/me/chores"} class="font-semibold">
        {Format.count(length(@item.chores),
          one: "Your chore was declined",
          many: "%d of your chores were declined"
        )}
      </.a>
      <span class="hint block">{declined_hint(@item.chores)}</span>
    </li>
    """
  end

  defp to_do_item(%{item: %{key: :letter}} = assigns) do
    ~H"""
    <li id="to-do-letter" class="flex flex-wrap items-center gap-3 py-3">
      <div class="flex-1 min-w-0">
        <strong class="block">Your {@item.letter.year} tax credit letter is ready</strong>
        <span class="hint">{letter_hours(@item.letter)}</span>
      </div>
      <.button
        id="to-do-letter-download"
        href={~p"/teams/#{@team}/me/tax-credit-letters/#{@item.letter.id}/pdf"}
      >
        Download letter
      </.button>
    </li>
    """
  end

  defp declined_hint([chore]),
    do:
      "#{chore.description}, #{Format.date_short(chore.date)}. Read why, then delete it or log it again."

  defp declined_hint(_chores), do: "Read why, then delete them or log them again."

  # "52 hours primary, 25 hours secondary", or a plain line for an old letter whose
  # hours did not parse.
  defp letter_hours(%{primary_minutes: primary, secondary_minutes: secondary})
       when is_integer(primary) and is_integer(secondary),
       do: "#{Format.duration(primary)} primary, #{Format.duration(secondary)} secondary"

  defp letter_hours(_letter), do: "Give it to the CRA with your tax return."

  attr :team, :map, required: true
  attr :charts, :map, required: true
  attr :map, :map, default: nil
  attr :team_admin?, :boolean, required: true

  defp pulse(assigns) do
    ~H"""
    <div id="team-pulse">
      <div class="chart-stats">
        <.stat
          id="stat-activities"
          value={Format.number(@charts.activities_ytd)}
          label={"Activities in #{@charts.year}"}
          href={~p"/teams/#{@team}/activities?when=past&sort=date-"}
          delta={versus(@charts.activities_ytd, @charts.activities_last_ytd)}
        >
          <.sparkline values={@charts.monthly_activities} />
        </.stat>
        <.stat
          id="stat-incidents"
          series={:incident}
          value={Format.number(@charts.incidents_ytd)}
          label={"Incidents in #{@charts.year}"}
          delta={versus(@charts.incidents_ytd, @charts.incidents_last_ytd)}
        >
          <.sparkline values={@charts.monthly_incidents} series={:incident} />
        </.stat>
        <.stat
          id="stat-hours"
          value={Format.hours(@charts.minutes_ytd)}
          label={"Member hours in #{@charts.year}"}
          delta={versus(div(@charts.minutes_ytd, 60), div(@charts.minutes_last_ytd, 60))}
        >
          <.sparkline values={@charts.monthly_hours} />
        </.stat>
        <.stat
          id="stat-members"
          value={Format.number(@charts.members)}
          label="Current members"
          href={if(@team_admin?, do: ~p"/teams/#{@team}/members")}
          delta={"#{@charts.members_joined} joined in #{@charts.year}"}
        />
      </div>
      <div class="card-grid">
        <section class="card span-7">
          <header>
            <h2 class="chart-title">Activities by month</h2>
            <.a navigate={~p"/teams/#{@team}/activities?when=past&sort=date-"}>
              All activities
            </.a>
          </header>
          <p class="chart-caption">The last 12 months</p>
          <.column_chart
            id="activities-by-month"
            columns={@charts.activity_columns}
            series={TeamDashboardCharts.series()}
            caption="Activities by month"
          />
        </section>
        <section class="card span-5">
          <header>
            <h2 class="chart-title">Where the team went</h2>
          </header>
          <p :if={@map} class="chart-caption">
            The last 12 months. Large dots are the last 30 days.
          </p>
          <.activity_map
            :if={@map}
            id="activity-map"
            map={@map}
            label="Map of activities in the last 12 months"
            overlay={false}
          />
          <p :if={!@map} id="activity-map" class="chart-caption">
            No activities with a place in {D4H.service_name(@team)} in the last 12 months.
          </p>
        </section>
        <section class="card">
          <header>
            <h2 class="chart-title">Every day out</h2>
          </header>
          <p class="chart-caption">The last 12 months</p>
          <.calendar id="activity-calendar" days={@charts.calendar_days} />
        </section>
      </div>
    </div>
    """
  end

  # Against the same days of last year: "12 more than this time last year".
  defp versus(now, before) do
    cond do
      now > before -> "#{Format.number(now - before)} more than this time last year"
      now < before -> "#{Format.number(before - now)} fewer than this time last year"
      true -> "Same as this time last year"
    end
  end

  # The refresh's own progress, such as "Members: 120/480 (25%)", after the slow thing.
  defp refreshing_text(team, "Refreshing"), do: "Refreshing from #{D4H.service_name(team)}…"
  defp refreshing_text(team, stage), do: "Refreshing from #{D4H.service_name(team)}… #{stage}"

  # Progress messages arrive at every stage of a full refresh; the page recounts once the
  # refresh or sync is done, not at each stage.
  def handle_info({:team_refreshed, %Team{} = updated_team}, socket) do
    if updated_team.id == socket.assigns.current_team.id do
      socket = assign(socket, current_team: updated_team)

      if Team.refresh_state(updated_team.d4h_refresh_result) == :refreshing do
        view_data = %{socket.assigns.view_data | refresh_result: updated_team.d4h_refresh_result}
        {:noreply, assign(socket, view_data: view_data)}
      else
        {:noreply, assign_page(socket, updated_team)}
      end
    else
      {:noreply, socket}
    end
  end

  # A second refresh while one runs does nothing; the button is disabled, but a page open
  # in 2 tabs can still send one.
  # Only team admins refresh; a member's page has no button, but an event can still come.
  def handle_event("refresh", _params, %{assigns: %{team_admin?: false}} = socket),
    do: {:noreply, socket}

  def handle_event("refresh", _params, socket) do
    if refreshing?(socket.assigns.view_data),
      do: {:noreply, socket},
      else: start_refresh(socket)
  end

  defp start_refresh(socket) do
    %{team_id: socket.assigns.current_team.id}
    |> RefreshTeamDataWorker.new()
    |> Oban.insert()

    view_data = %{socket.assigns.view_data | refresh_result: "Refreshing"}

    {:noreply, assign(socket, view_data: view_data)}
  end

  defp refreshing?(view_data), do: Team.refresh_state(view_data.refresh_result) == :refreshing
end

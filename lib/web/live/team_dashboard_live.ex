defmodule Web.TeamDashboardLive do
  use Web, {:live_view_app_layout, access: :team}

  import Web.Components.ActivityMap
  import Web.Components.Chart
  import Web.Components.ActivityPanel
  import Web.Components.OpenInMaps
  import Web.Components.PersonHead

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Certificate
  alias App.Model.Chore
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Model.WhiteboardNote
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
  alias Web.Components.Reply
  alias Web.Components.ReplyControl
  alias Web.WhiteboardText

  # The top half is what needs doing: what's next, and what needs a team admin. The lower
  # half is the team's year, loaded after it so the work never waits on the charts (#205).
  #
  # Members open it too (#406) and see what a team admin sees: Next up, Coming up, and
  # the team's year, plus For you to do. A member replies to the activities they're
  # invited to from Next up and Coming up (#444). Team admins also get Take attendance,
  # Needs attention, and Refresh now. A team admin who is a member gets both lists.
  # Everyone reads the whiteboard (#515) in a strip under Next up: its Important notes, or
  # its newest, at most 2. Posting and archiving are on the Whiteboard page.

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
      |> assign(org_name: WhiteboardText.org_name(current_team))
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
    |> assign_notes(team, now)
    |> assign(replier: Reply.replier(socket.assigns, now))
    |> assign_replies()
    |> assign_member(now)
  end

  defp assign_notes(socket, team, now) do
    notes = if Team.whiteboard?(team), do: WhiteboardNote.live(team, now), else: []
    {shown, more} = WhiteboardNote.for_dashboard(notes)
    assign(socket, notes: shown, more_notes: more)
  end

  # Next up's count, and the replier's invitations to Next up and Coming up, again after
  # a reply.
  defp assign_replies(socket) do
    %{current_team: team, view_data: view_data, replier: replier} = socket.assigns
    ids = Enum.map(List.wrap(view_data.next_up) ++ view_data.coming_up, & &1.id)

    assign(socket,
      counts: Attendance.reply_counts(team, ids),
      invitations: if(replier, do: Attendance.invitations(replier, ids), else: %{})
    )
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
      if Team.chores?(member.team),
        do: Chore.get_all_for_member(member, status: :declined),
        else: []

    certificates =
      if Team.certificates?(member.team),
        do: Certificate.get_open_for_member(member),
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
          chores,
          certificates
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
    <.person_head id="team-head" class="team-head mb-6" name={@current_team.name}>
      <:picture>
        <img
          :if={@has_logo}
          id="team-logo"
          src={~p"/teams/#{@current_team}/logo?shape=fit"}
          class="team-head-logo"
          alt="Team logo"
        />
        <span :if={!@has_logo} id="team-initials" class="team-head-logo is-initials">
          {team_initials(@current_team.name)}
        </span>
      </:picture>
      <:line>
        <.refresh_line
          team={@current_team}
          view_data={@view_data}
          now={@now}
          team_admin?={@team_admin?}
        />
      </:line>
    </.person_head>

    <.next_up_card
      :if={@view_data.next_up}
      team={@current_team}
      activity={@view_data.next_up}
      counts={@counts[@view_data.next_up.id]}
      reply={reply_assigns(assigns, @view_data.next_up)}
      maps_app={@current_user.maps_app}
      now={@now}
      team_admin?={@team_admin?}
    />

    <.whiteboard
      :if={@notes != []}
      team={@current_team}
      notes={@notes}
      more={@more_notes}
      org_name={@org_name}
    />

    <div class="card-grid items-start">
      <.coming_up
        team={@current_team}
        activities={@view_data.coming_up}
        replies={Enum.map(@view_data.coming_up, &reply_assigns(assigns, &1))}
        now={@now}
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

  # When SAR Duty last refreshed, Refresh now for team admins, and Open D4H for everyone
  # on a D4H team. While a refresh runs, its progress takes the line and Refresh now
  # goes, so nobody presses it twice.
  defp refresh_line(assigns) do
    assigns = assign(assigns, :refreshing?, refreshing?(assigns.view_data))

    ~H"""
    <.spinner :if={@refreshing?} id="refreshing" class="text-link">
      {refreshing_text(@view_data.refresh_result)}
    </.spinner>
    <span :if={!@refreshing?} id="d4h-updated">{refreshed_ago(@team, @now)}</span>
    <span :if={@team_admin? and !@refreshing?}>
      <span aria-hidden="true">·</span>
      <.button id="refresh-now" type="button" variant={:link} size={:sm} phx-click="refresh">
        Refresh now
      </.button>
    </span>
    <span :if={!D4H.records?(@team)} class="whitespace-nowrap">
      <span aria-hidden="true">·</span>
      <.a id="open-d4h" external={true} href={D4H.build_url(@team, "/dashboard")}>Open {D4H.service_name(
        @team
      )}</.a>
    </span>
    """
  end

  # "SF" for South Fraser SAR, in the logo's place until the team saves one.
  defp team_initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  # The reply control's assigns for an activity, or nil when the replier can't reply to
  # it: not invited, or it has started.
  defp reply_assigns(assigns, activity) do
    invitation = assigns.invitations[activity.id]

    if Reply.open?(invitation, activity, assigns.now) do
      %{
        team: assigns.current_team,
        activity: activity,
        member: assigns.replier,
        invitation: invitation,
        user: assigns.current_user,
        viewing_as: assigns.viewing_as
      }
    end
  end

  attr :team, :map, required: true
  attr :activity, :map, required: true
  attr :counts, :map, required: true
  attr :reply, :map, default: nil, doc: "the reply control's assigns, nil for none"
  attr :maps_app, :string, required: true
  attr :now, :any, required: true
  attr :team_admin?, :boolean, required: true

  # The team's next activity, the same panel as the activity's page, with its title and
  # place. Its count goes in the place's line rather than a line of its own.
  defp next_up_card(assigns) do
    ~H"""
    <.activity_panel
      id="next-up"
      label="Next up"
      activity={@activity}
      team={@team}
      now={@now}
      take_attendance?={Activity.take_attendance?(@activity, @team_admin?, @now)}
    >
      <.activity_kind_mark activity={@activity} class="text-sm" />
      <h2 class="activity-panel-title">
        <.a navigate={~p"/teams/#{@team}/activities/#{@activity.id}"}>{@activity.title}</.a>
      </h2>
      <p id="next-up-hint" class="hint">{where_and_when(@activity, @counts, @now)}</p>
      <.open_in_maps
        id="next-up-maps"
        app={@maps_app}
        coordinate={Activity.pin(@activity)}
        address={@activity.address}
        label={@activity.title}
      />
      <:reply :if={@reply}>
        <.live_component module={ReplyControl} id="next-up-reply" {@reply} />
      </:reply>
    </.activity_panel>
    """
  end

  # "Murrin Park · in 3 hours · 6 signed up", without the place when D4H has none.
  defp where_and_when(activity, counts, now) do
    started? = Activity.started?(activity, now)

    [
      activity.address,
      Format.starts_in(activity.started_at, now),
      Reply.yes_text(counts, started?)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  attr :team, :map, required: true
  attr :activities, :list, required: true
  attr :replies, :list, required: true, doc: "each activity's reply assigns, or nil"
  attr :now, :any, required: true

  # The title is each row's link, so a row can hold the reply's buttons.
  defp coming_up(assigns) do
    ~H"""
    <section id="coming-up" class="card span-6">
      <header>
        <h2 class="chart-title">Coming up</h2>
        <span class="hint">Next 14 days</span>
      </header>
      <p :if={@activities == []} id="coming-up-empty" class="chart-caption">
        No activities planned.
      </p>
      <ul :if={@activities != []} id="coming-up-list" class="dash-list">
        <li
          :for={{activity, reply} <- Enum.zip(@activities, @replies)}
          id={"coming-up-#{activity.id}"}
        >
          <.coming_up_row team={@team} activity={activity} reply={reply} now={@now} />
        </li>
      </ul>
      <footer class="action">
        <.a navigate={~p"/teams/#{@team}/activities?when=future&sort=date"}>All future activities</.a>
      </footer>
    </section>
    """
  end

  attr :team, :map, required: true
  attr :activity, :map, required: true
  attr :reply, :map, default: nil
  attr :now, :any, required: true

  defp coming_up_row(assigns) do
    ~H"""
    <div class="dash-row">
      <div class="dash-row-when">
        <strong>{Format.day_coming_up(@activity.started_at, @now, @team.timezone)}</strong>
        <span class="text-text-muted">
          {Format.time_short(@activity.started_at, @team.timezone)}
        </span>
      </div>
      <div class="dash-row-title">
        <.activity_kind_mark activity={@activity} class="text-sm" />
        <.a navigate={~p"/teams/#{@team}/activities/#{@activity.id}"}>{@activity.title}</.a>
        <.live_component
          :if={@reply}
          module={ReplyControl}
          id={"coming-up-reply-#{@activity.id}"}
          size={:sm}
          {@reply}
        />
      </div>
    </div>
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

  defp attention_path(team, %{key: :watch_missing}), do: ~p"/teams/#{team}/settings/members"

  defp attention_path(team, %{key: :retiring_missing}), do: ~p"/teams/#{team}/settings/members"

  defp attention_path(team, %{key: :retiring}),
    do: ~p"/teams/#{team}/equipment?place=retiring"

  defp attention_path(team, %{key: :retiring_access}),
    do: ~p"/teams/#{team}/members?standing=retiring&access=some"

  defp attention_path(team, %{key: :retiring_clear}),
    do: ~p"/teams/#{team}/members?standing=retiring&items=none"

  defp attention_path(team, %{key: :group_changes}), do: ~p"/teams/#{team}/groups"

  defp attention_path(team, %{key: :certificates}), do: ~p"/teams/#{team}/certificates"

  defp attention_path(team, %{key: key}) when key in [:chores, :chores_to_send],
    do: ~p"/teams/#{team}/chores"

  defp attention_path(team, %{key: key, activity_id: activity_id})
       when key in [:attendance_to_send, :no_shows],
       do: ~p"/teams/#{team}/activities/#{activity_id}/attendance"

  defp attention_path(team, %{key: :letters, year: year}),
    do: ~p"/teams/#{team}/tax-credit-letters?year=#{year}"

  attr :team, :map, required: true
  attr :notes, :list, required: true
  attr :more, :integer, required: true
  attr :org_name, :string, default: nil

  # One line a note, its rule blue when Important, and no title: the grey says what it is.
  # A tap opens a clipped note in place; the full text is always in the markup, so a
  # screen reader reads it all.
  defp whiteboard(assigns) do
    ~H"""
    <section id="whiteboard" class="whiteboard" aria-labelledby="whiteboard-title">
      <h2 id="whiteboard-title" class="sr-only">Whiteboard</h2>
      <ul class="whiteboard-notes">
        <li
          :for={note <- @notes}
          id={"whiteboard-note-#{note.id}"}
          class={["whiteboard-note", note.important && "is-important"]}
        >
          <p
            class="whiteboard-text"
            phx-click={JS.toggle_class("is-open", to: "#whiteboard-note-#{note.id}")}
          >
            <span :if={note.important} class="sr-only">Important:</span>
            <span :if={!WhiteboardNote.team_note?(note)} class="text-text-muted">
              {WhiteboardText.speaker(@org_name)}
            </span>
            <WhiteboardText.note_text note={note} tag={false} />
          </p>
          <WhiteboardText.note_link note={note} class="whiteboard-link" />
        </li>
      </ul>
      <p :if={@more > 0} class="action whiteboard-more">
        <.a id="whiteboard-more" navigate={~p"/teams/#{@team}/whiteboard"}>{Format.count(
          @more,
          one: "%d more note",
          many: "%d more notes"
        )}</.a>
      </p>
    </section>
    """
  end

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

  # With certificates on (#493), the link opens the form for the qualification.
  defp to_do_item(%{item: %{key: :qualification}} = assigns) do
    assigns = assign(assigns, :certificates?, Team.certificates?(assigns.team))

    ~H"""
    <li id={"to-do-qualification-#{@item.award.qualification_id}"} class="py-3">
      <.a
        navigate={
          if @certificates?,
            do: ~p"/teams/#{@team}/certificates/new?#{[qualification: @item.award.qualification_id]}",
            else: ~p"/teams/#{@team}/me"
        }
        class="font-semibold"
      >Your {@item.award.qualification.title} expires in {Format.days(@item.days)}</.a>
      <span :if={@certificates?} class="hint block">Renewed it? Add the new certificate.</span>
      <span :if={!@certificates?} class="hint block">
        Renewed it? Give the new certificate to a team admin.
      </span>
    </li>
    """
  end

  defp to_do_item(%{item: %{key: :declined_certificates}} = assigns) do
    ~H"""
    <li id="to-do-declined-certificates" class="py-3">
      <.a
        navigate={~p"/teams/#{@team}/me"}
        class="font-semibold"
      >{Format.count(length(@item.certificates),
        one: "Your certificate was declined",
        many: "%d of your certificates were declined"
      )}</.a>
      <span class="hint block">{declined_certificate_hint(@item.certificates)}</span>
    </li>
    """
  end

  defp to_do_item(%{item: %{key: :declined_chores}} = assigns) do
    ~H"""
    <li id="to-do-declined-chores" class="py-3">
      <.a
        navigate={Web.ChoreCollectionLive.view_path(@team, :yours)}
        class="font-semibold"
      >{Format.count(length(@item.chores),
        one: "Your chore was declined",
        many: "%d of your chores were declined"
      )}</.a>
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

  defp declined_certificate_hint([certificate]),
    do: "#{Web.CertificateText.title(certificate)}. Read why, then delete it or send it again."

  defp declined_certificate_hint(_certificates),
    do: "Read why, then delete them or send them again."

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
          href={~p"/teams/#{@team}/members"}
          delta={"#{@charts.members_joined} joined in #{@charts.year}"}
        />
      </div>
      <div class="card-grid">
        <section class="card span-7">
          <header>
            <h2 class="chart-title">Activities by month</h2>
            <.a navigate={~p"/teams/#{@team}/activities?when=past&sort=date-"}>All activities</.a>
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
            No activities with a place in the last 12 months.
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
  defp refreshing_text("Refreshing"), do: "Refreshing…"
  defp refreshing_text(stage), do: "Refreshing… #{stage}"

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

  def handle_info({:replied, _attendance}, socket), do: {:noreply, assign_replies(socket)}

  def handle_info({:reply_failed, text}, socket), do: {:noreply, put_flash(socket, :error, text)}

  # A second refresh while one runs does nothing; the button is disabled, but a page open
  # in 2 tabs can still send one. Only team admins send it: Web.UserAuth drops a member's.
  def handle_event("refresh", _params, socket) do
    if refreshing?(socket.assigns.view_data),
      do: {:noreply, socket},
      else: start_refresh(socket)
  end

  defp start_refresh(socket) do
    RefreshTeamDataWorker.enqueue(socket.assigns.current_team)

    view_data = %{socket.assigns.view_data | refresh_result: "Refreshing"}

    {:noreply, assign(socket, view_data: view_data)}
  end

  defp refreshing?(view_data), do: Team.refresh_state(view_data.refresh_result) == :refreshing
end

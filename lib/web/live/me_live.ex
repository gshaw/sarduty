defmodule Web.MeLive do
  use Web, {:live_view_app_layout, access: :member}

  import Web.Components.Chart, only: [stat: 1]
  import Web.Components.MemberLetter
  import Web.Components.MilestoneList

  alias App.Adapter.D4H
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.ViewData.MemberRecords
  alias App.ViewData.Milestones
  alias Service.Format
  alias Web.QualificationText

  # Your membership (#406), /teams/:subdomain/me: a member's own page on one team. Their
  # latest activities, from any year so it is never empty on January 1, and their
  # qualifications in the main column; their ID card, latest tax credit letter, contact
  # details, and milestones in a sidebar, split by space, not boxes (/styles/card).
  # `current_member` comes from the login (Web.UserAuth, :ensure_team_access), never from
  # the URL.
  def mount(_params, _session, socket) do
    member = socket.assigns.current_member
    team = member.team
    now = DateTime.utc_now()
    attended = MemberRecords.attended(member, now)

    socket =
      socket
      |> assign(:page_title, member.name)
      |> assign(member: member, team: team, now: now)
      |> assign(:today, now |> DateTime.shift_zone!(team.timezone) |> DateTime.to_date())
      |> assign_activities(attended, now)
      |> assign(:qualifications, MemberRecords.qualifications(member, now))
      |> assign(:card, team.id_cards_enabled && MemberCard.find_current(team, member))
      |> assign(:letter, member |> TaxCreditLetter.get_all_for_member() |> List.first())
      |> assign(:milestones, member |> milestones(attended, now) |> Enum.take(5))

    {:ok, socket}
  end

  # The 10 latest, the year of the latest for the year page's link, and the last 12
  # months as 3 numbers.
  defp assign_activities(socket, attended, now) do
    assign(socket,
      activities: Enum.take(attended, 10),
      latest_year: latest_year(attended, socket.assigns.team.timezone),
      stats: year_stats(attended, now)
    )
  end

  defp latest_year([latest | _rest], timezone),
    do: Service.YearRange.year_in(latest.started_at, timezone)

  defp latest_year([], _timezone), do: nil

  # Each activity counted once, and every attended row's time.
  defp year_stats(attended, now) do
    a_year_ago = DateTime.shift(now, year: -1)
    last_12 = Enum.filter(attended, &DateTime.after?(&1.started_at, a_year_ago))
    activities = last_12 |> Enum.map(& &1.activity) |> Enum.uniq_by(& &1.id)

    %{
      activities: length(activities),
      incidents: Enum.count(activities, &(&1.activity_kind == "incident")),
      minutes: last_12 |> Enum.map(&MemberRecords.minutes/1) |> Enum.sum()
    }
  end

  defp milestones(member, attended, now) do
    attended
    |> Milestones.build(
      member.joined_at,
      MemberAwayPeriod.for_member(member),
      now,
      member.team.timezone
    )
  end

  def render(assigns) do
    ~H"""
    <div class="person-head">
      <%!-- Ignored on update, so the photo a failed load removed stays gone. --%>
      <span id="member-avatar" class="avatar avatar-lg" phx-update="ignore">
        {Web.Navigation.initials(@member.name)}
        <img id="member-photo" src={~p"/teams/#{@team}/me/image"} alt="" onerror="this.remove()" />
      </span>
      <div class="min-w-0">
        <h1 class="title mb-0">{@member.name}</h1>
        <p :if={@member.joined_at} id="member-since" class="hint mt-1 mb-0">
          Member since {Format.month_year_long(@member.joined_at, @team.timezone)}
        </p>
      </div>
    </div>

    <div class="membership mt-6">
      <div class="min-w-0">
        <.activities
          team={@team}
          latest_year={@latest_year}
          activities={@activities}
          stats={@stats}
        />
        <.qualifications team={@team} now={@now} qualifications={@qualifications} />
      </div>
      <aside class="membership-aside">
        <div :if={@team.id_cards_enabled or @letter} class="membership-aside-top">
          <.id_card :if={@team.id_cards_enabled} team={@team} card={@card} />
          <.member_letter
            :if={@letter}
            id="letter"
            team={@team}
            letter={@letter}
            year={@letter.year}
            hours={false}
          />
        </div>
        <div class="membership-aside-bottom">
          <.contact_details
            team={@team}
            member={@member}
          />
          <.milestones milestones={@milestones} today={@today} />
        </div>
      </aside>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :latest_year, :integer, default: nil
  attr :activities, :list, required: true
  attr :stats, :map, required: true

  defp activities(assigns) do
    ~H"""
    <section id="activities">
      <h2 class="heading">Latest activities</h2>
      <div :if={@stats.activities > 0} id="year-stats">
        <p class="chart-caption mb-2">The last 12 months</p>
        <div class="chart-stats">
          <.stat id="stat-activities" value={Format.number(@stats.activities)} label="Activities" />
          <.stat
            id="stat-incidents"
            series={:incident}
            value={Format.number(@stats.incidents)}
            label="Incidents"
          />
          <.stat id="stat-hours" value={Format.hours(@stats.minutes)} label="Hours" />
        </div>
      </div>
      <.empty_state :if={@activities == []} id="no-activities" title="No activities yet">
        Activities you attend show here after SAR Duty refreshes from {D4H.service_name(@team)}.
        <:action>
          <.a id="coming-up-link" navigate={~p"/teams/#{@team}/activities"}>Activities coming up</.a>
        </:action>
      </.empty_state>
      <.table
        :if={@activities != []}
        id="activities-list"
        rows={@activities}
        row_id={&"activities-list-#{&1.id}"}
      >
        <:col :let={attendance} label="Date" class="w-px whitespace-nowrap">
          {Format.date_short(attendance.started_at, @team.timezone)}
        </:col>
        <:col :let={attendance} label="Activity">
          <.a navigate={~p"/teams/#{@team}/activities/#{attendance.activity.id}"}>
            {attendance.activity.title}
          </.a>
        </:col>
        <:col :let={attendance} label="Kind" class="w-px whitespace-nowrap max-md:hidden">
          <.activity_kind_mark activity={attendance.activity} />
        </:col>
        <:col :let={attendance} label="Time" align="right" class="w-px whitespace-nowrap">
          {Format.duration(MemberRecords.minutes(attendance))}
        </:col>
      </.table>
      <p :if={@activities != []} class="action mt-2">
        <.a
          id="all-activities"
          navigate={~p"/teams/#{@team}/me/activities?year=#{@latest_year}"}
        >
          All your activities
        </.a>
      </p>
    </section>
    """
  end

  attr :team, :map, required: true
  attr :now, :any, required: true
  attr :qualifications, :list, required: true

  defp qualifications(assigns) do
    ~H"""
    <section id="qualifications" class="mt-8">
      <h2 class="heading">Qualifications</h2>
      <.empty_state :if={@qualifications == []} id="no-qualifications" title="No qualifications yet">
        Qualifications your team records in {D4H.service_name(@team)} show here.
      </.empty_state>
      <.table
        :if={@qualifications != []}
        id="qualifications-list"
        rows={@qualifications}
        row_id={&"qualifications-list-#{&1.award.qualification_id}"}
        row_class={&QualificationText.row_class/1}
      >
        <:col :let={row} label="Qualification">{row.award.qualification.title}</:col>
        <:col :let={row} label="Expires" class="whitespace-nowrap">
          {QualificationText.expires(row.award, @now, @team.timezone)}
          <.badge :if={row.status == :expiring} kind={:warning}>
            {QualificationText.days_left(row)}
          </.badge>
        </:col>
      </.table>
    </section>
    """
  end

  attr :team, :map, required: true
  attr :card, :map, default: nil

  defp id_card(%{card: nil} = assigns) do
    ~H"""
    <div id="id-card">
      <h2 class="chart-title mb-1">ID card</h2>
      <p id="no-card" class="hint mb-0">
        No ID card yet. Your team admins issue them. Ask one for yours.
      </p>
    </div>
    """
  end

  defp id_card(assigns) do
    ~H"""
    <div id="id-card">
      <h2 class="chart-title mb-1">ID card</h2>
      <p class="hint mb-2">
        Your ID card shows you are a current member of {@team.name}, with your endorsements.
        Show it at the door, or to another agency on a search.
      </p>
      <p class="hint">
        Anyone can verify it at <.a
          id="card-verify-link"
          href={verify_url(@card)}
          class="whitespace-nowrap"
        >{verify_label(@card)}</.a>.
      </p>
      <div
        :if={BuildApplePass.configured?() or BuildGooglePass.configured?()}
        class="flex flex-wrap gap-2"
      >
        <.button
          :if={BuildApplePass.configured?()}
          id="apple-pass"
          href={~p"/teams/#{@team}/me/card/apple-wallet"}
        >
          Add to Apple Wallet
        </.button>
        <.button
          :if={BuildGooglePass.configured?()}
          id="google-pass"
          href={~p"/teams/#{@team}/me/card/google-wallet"}
        >
          Add to Google Wallet
        </.button>
      </div>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :member, :map, required: true

  defp contact_details(assigns) do
    ~H"""
    <div id="contact-details">
      <h2 class="chart-title mb-1">Contact details</h2>
      <dl class="mb-3">
        <dt>Mobile</dt>
        <dd id="contact-mobile">{@member.phone || "None"}</dd>
        <dt>Address</dt>
        <dd id="contact-address">{@member.address || "None"}</dd>
        <dt>Emergency contact</dt>
        <dd id="contact-emergency">{contact_line(@member.primary_emergency_contact)}</dd>
      </dl>
      <p class="action mb-0">
        <.a id="change-details" navigate={~p"/teams/#{@team}/me/details"}>
          Change contact details
        </.a>
      </p>
    </div>
    """
  end

  attr :milestones, :list, required: true
  attr :today, Date, required: true

  defp milestones(assigns) do
    ~H"""
    <div id="milestones">
      <h2 class="chart-title mb-1">Milestones</h2>
      <p :if={@milestones == []} id="no-milestones" class="hint mb-0">
        No milestones yet. The first comes with your first incident, 100 hours, or 1 year on
        the team.
      </p>
      <.milestone_list
        :if={@milestones != []}
        id="milestones-list"
        milestones={@milestones}
        today={@today}
      />
    </div>
    """
  end

  defp contact_line(%{"name" => name} = contact) when is_binary(name),
    do:
      [name, Service.Phone.format(contact["primary_phone"])]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" · ")

  defp contact_line(_contact), do: "None"

  defp verify_label(card), do: "#{Web.VerifyHost.host()}/#{MemberCard.format_code(card.code)}"

  defp verify_url(card), do: "#{Web.VerifyHost.url()}/#{MemberCard.format_code(card.code)}"
end

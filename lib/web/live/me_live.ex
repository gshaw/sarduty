defmodule Web.MeLive do
  use Web, {:live_view_app_layout, access: :member}

  import Web.Components.Chart, only: [stat: 1]
  import Web.Components.Equipment, only: [held_table: 1]
  import Web.Components.MemberLetter
  import Web.Components.MilestoneList
  import Web.Components.PersonHead
  import Web.ChoreText, only: [status_badge: 1]

  alias App.Adapter.D4H
  alias App.Model.Certificate
  alias App.Model.Chore
  alias App.Model.EquipmentItem
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.SaveCertificate
  alias App.ViewData.EquipmentList
  alias App.ViewData.MemberMilestones
  alias App.ViewData.MemberRecords
  alias Service.Format
  alias Web.Components.MemberSidebar
  alias Web.QualificationText

  # Your membership (#406), /teams/:subdomain/me: a member's own page on one team. Their
  # latest activities, from any year so it is never empty on January 1, and their
  # qualifications and the equipment they hold in the main column; their ID card, latest
  # tax credit letter, contact details, and milestones in a sidebar, split by space, not
  # boxes (/styles/card).
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
      |> assign(:standing, MemberAwayPeriod.standing_today(member, team.timezone, now))
      |> assign_activities(attended, now)
      |> assign(:chores, latest_chores(member))
      |> assign(:qualifications, MemberRecords.qualifications(member, now))
      |> assign(:certificates, sent_certificates(member))
      |> assign(:card, team.id_cards_enabled && MemberCard.find_current(team, member))
      |> assign(:letter, member |> TaxCreditLetter.get_all_for_member() |> List.first())
      |> assign(:milestones, MemberMilestones.for_member(member, now, attended))
      |> assign(:equipment, team |> EquipmentItem.held_by(member) |> EquipmentList.held_rows())

    {:ok, socket}
  end

  # The 10 latest, when the last was for the header, the year of the latest for the year
  # page's link, and the last 12 months as 3 numbers.
  defp assign_activities(socket, attended, now) do
    assign(socket,
      activities: Enum.take(attended, 10),
      last_attended_at: attended |> List.first() |> then(&(&1 && &1.started_at)),
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

  # The member's waiting and declined certificates (#493), on a team with certificates
  # on. Nil hides Add a certificate.
  defp sent_certificates(member),
    do: if(Team.certificates?(member.team), do: Certificate.get_open_for_member(member))

  # A member's latest chores (#341), on a team with chores on. Nil hides the section.
  defp latest_chores(member),
    do: if(Team.chores?(member.team), do: Chore.get_all_for_member(member, limit: 5))

  def render(assigns) do
    ~H"""
    <%!-- Away shows as a reminder; a retired member can't log in. --%>
    <.person_head
      id="member-head"
      name={@member.name}
      photo={~p"/teams/#{@team}/me/image"}
      standing={@standing}
      facts={facts(@member, @last_attended_at, @team.timezone)}
    />

    <div class="membership mt-6">
      <div class="min-w-0">
        <.activities
          team={@team}
          latest_year={@latest_year}
          activities={@activities}
          stats={@stats}
        />
        <.chores :if={@chores} team={@team} chores={@chores} />
        <.qualifications
          team={@team}
          now={@now}
          qualifications={@qualifications}
          certificates={@certificates}
        />
        <.equipment :if={@equipment != []} team={@team} rows={@equipment} />
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
          <.stat
            id="stat-activities"
            value={Format.number(@stats.activities)}
            label={Format.count(@stats.activities, one: "Activity", many: "Activities")}
          />
          <.stat
            id="stat-incidents"
            series={:incident}
            value={Format.number(@stats.incidents)}
            label={Format.count(@stats.incidents, one: "Incident", many: "Incidents")}
          />
          <.stat
            id="stat-hours"
            value={Format.hours(@stats.minutes)}
            label={Format.count(div(round(@stats.minutes), 60), one: "Hour", many: "Hours")}
          />
        </div>
      </div>
      <.empty_state :if={@activities == []} id="no-activities" title="No activities yet">
        Activities you attend show here after SAR Duty refreshes from {D4H.service_name(@team)}.
        <:action>
          <p class="action">
            <.a id="coming-up-link" navigate={~p"/teams/#{@team}/activities"}>Activities coming up</.a>
          </p>
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
          <.a navigate={~p"/teams/#{@team}/activities/#{attendance.activity.id}"}>{attendance.activity.title}</.a>
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
        >All your activities</.a>
      </p>
    </section>
    """
  end

  attr :team, :map, required: true
  attr :chores, :list, required: true

  defp chores(assigns) do
    ~H"""
    <section id="chores" class="mt-8">
      <.heading_row>
        <h2 class="heading">Chores</h2>
        <:action>
          <.a id="chore-log" navigate={~p"/teams/#{@team}/me/chores/new"}>New chore</.a>
        </:action>
      </.heading_row>
      <.empty_state :if={@chores == []} id="no-chores" title="No chores yet">
        Log a chore after you do one, such as fixing equipment or admin. It counts once a team admin accepts it.
      </.empty_state>
      <.table :if={@chores != []} id="chores-list" rows={@chores} row_id={&"chores-list-#{&1.id}"}>
        <:col :let={chore} label="Date" class="w-px whitespace-nowrap">
          {Format.date_short(chore.date)}
        </:col>
        <:col :let={chore} label="What you did">
          {chore.description}
          <span class="hint block">{chore.chore_category.title}</span>
        </:col>
        <:col :let={chore} label="" class="w-px whitespace-nowrap">
          <.status_badge chore={chore} />
        </:col>
        <:col :let={chore} label="Time" align="right" class="w-px whitespace-nowrap">
          {Format.duration(chore.minutes)}
        </:col>
      </.table>
      <p :if={@chores != []} class="action mt-2">
        <.a id="all-chores" navigate={~p"/teams/#{@team}/me/chores"}>All your chores</.a>
      </p>
    </section>
    """
  end

  attr :team, :map, required: true
  attr :now, :any, required: true
  attr :qualifications, :list, required: true
  attr :certificates, :list, default: nil

  # Certificates the member sent (#493) sit at the top of the one table, so it reads the
  # same on a team on SAR Duty Records.
  defp qualifications(assigns) do
    assigns =
      assign(
        assigns,
        :rows,
        Enum.map(assigns.certificates || [], &%{certificate: &1}) ++ assigns.qualifications
      )

    ~H"""
    <section id="qualifications" class="mt-8">
      <.heading_row>
        <h2 class="heading">Qualifications</h2>
        <:action :if={@certificates}>
          <.a id="certificate-add" navigate={~p"/teams/#{@team}/me/certificates/new"}>Add a certificate</.a>
        </:action>
      </.heading_row>
      <.empty_state :if={@rows == []} id="no-qualifications" title="No qualifications yet">
        Qualifications your team records in {D4H.service_name(@team)} show here.
      </.empty_state>
      <.table
        :if={@rows != []}
        id="qualifications-list"
        rows={@rows}
        row_id={&row_id/1}
        row_class={&row_class/1}
      >
        <:col :let={row} label="Qualification">
          <.sent_certificate :if={row[:certificate]} team={@team} certificate={row.certificate} />
          <%= if row[:award] do %>
            {row.award.qualification.title}
            <span :if={row.award.d4h_document_id} class="hint block">
              <.a
                id={"certificate-#{row.award.id}"}
                href={~p"/teams/#{@team}/me/qualifications/#{row.award.id}/certificate"}
              >Certificate</.a>
            </span>
          <% end %>
        </:col>
        <:col :let={row} label="Expires" class="whitespace-nowrap">
          <%= if certificate = row[:certificate] do %>
            {certificate.ends_on && Format.date_short(certificate.ends_on)}
            <.badge :if={certificate.status == :waiting}>Waiting</.badge>
            <.badge :if={certificate.status == :declined} kind={:warning}>Declined</.badge>
          <% else %>
            {QualificationText.expires(row.award, @now, @team.timezone)}
            <.badge :if={row.status == :expiring} kind={:warning}>
              {QualificationText.days_left(row)}
            </.badge>
          <% end %>
        </:col>
      </.table>
    </section>
    """
  end

  defp row_id(%{certificate: certificate}),
    do: "qualifications-list-certificate-#{certificate.id}"

  defp row_id(row), do: "qualifications-list-#{row.award.qualification_id}"

  defp row_class(%{certificate: _certificate}), do: nil
  defp row_class(row), do: QualificationText.row_class(row)

  attr :team, :map, required: true
  attr :certificate, :map, required: true

  # Waiting: changed from its link until it goes to D4H. Declined: why, until deleted.
  defp sent_certificate(assigns) do
    ~H"""
    <%= if @certificate.status == :waiting and Certificate.member_can_change?(@certificate) do %>
      <.a
        id={"certificate-edit-#{@certificate.id}"}
        navigate={~p"/teams/#{@team}/me/certificates/#{@certificate.id}/edit"}
      >{qualification_title(@certificate)}</.a>
    <% else %>
      {qualification_title(@certificate)}
    <% end %>
    <span :if={@certificate.status == :waiting} class="hint block">
      Sent {Format.date_short(@certificate.inserted_at, @team.timezone)}. A team admin adds it to {D4H.service_name(
        @team
      )}.
    </span>
    <span :if={@certificate.status == :declined} class="hint block">
      {@certificate.decline_reason}
    </span>
    <.a
      :if={@certificate.status == :declined}
      id={"certificate-delete-#{@certificate.id}"}
      href="#"
      phx-click="delete-certificate"
      phx-value-id={@certificate.id}
      data-confirm={"Delete your #{qualification_title(@certificate)} certificate?"}
    >Delete</.a>
    """
  end

  defp qualification_title(%{qualification: %{title: title}}), do: title
  defp qualification_title(_certificate), do: "Certificate"

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
      <dl>
        <dt>Mobile</dt>
        <dd id="contact-mobile">{Service.Phone.format(@member.phone) || "None"}</dd>
        <dt>Address</dt>
        <dd id="contact-address">{@member.address || "None"}</dd>
        <.emergency_contact
          id="contact-emergency"
          label="Emergency contact"
          contact={@member.primary_emergency_contact}
        />
        <.emergency_contact
          :if={MemberSidebar.shown?(@member.secondary_emergency_contact)}
          id="contact-emergency-2"
          label="Second emergency contact"
          contact={@member.secondary_emergency_contact}
        />
      </dl>
      <p class="action mb-0">
        <.a id="change-details" navigate={~p"/teams/#{@team}/me/details"}>Change contact details</.a>
      </p>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :rows, :list, required: true

  # Everything they hold, so they know what to bring back (#490), as a team admin sees it
  # on their Equipment tab. No links: item pages are for team admins.
  defp equipment(assigns) do
    ~H"""
    <section id="equipment" class="mt-8">
      <h2 class="heading">Equipment</h2>
      <.held_table id="equipment-list" rows={@rows} team={@team} links={false} />
    </section>
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

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :contact, :map, default: nil

  # As a team admin sees it on the member's page: the name, then each phone on its own
  # line.
  defp emergency_contact(assigns) do
    ~H"""
    <dt>{@label}</dt>
    <dd id={@id}>
      <%= if MemberSidebar.shown?(@contact) do %>
        {MemberSidebar.contact_name(@contact)}
        <span :for={phone <- MemberSidebar.phones(@contact)} class="block">
          {Service.Phone.format(phone)}
        </span>
      <% else %>
        None
      <% end %>
    </dd>
    """
  end

  def handle_event("delete-certificate", %{"id" => id}, socket) do
    member = socket.assigns.member
    certificate = Certificate.find_for_member!(member, id)

    socket =
      case SaveCertificate.delete_own(member, certificate) do
        :ok -> put_flash(socket, :info, "Deleted your certificate.")
        {:error, :decided} -> put_flash(socket, :error, "This certificate cannot be deleted now.")
      end

    {:noreply, assign(socket, :certificates, sent_certificates(member))}
  end

  defp verify_label(card), do: "#{Web.VerifyHost.host()}/#{MemberCard.format_code(card.code)}"

  defp verify_url(card), do: "#{Web.VerifyHost.url()}/#{MemberCard.format_code(card.code)}"
end

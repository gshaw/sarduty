defmodule Web.MeLive do
  use Web, {:live_view_app_layout, access: :member, view_events: ["year"]}

  import Web.Components.Chart, only: [stat: 1]
  import Web.Components.Equipment, only: [held_table: 1]
  import Web.Components.MeYear
  import Web.Components.MemberLetter
  import Web.Components.MilestoneList
  import Web.Components.PersonHead
  import Web.ChoreText, only: [status_badge: 1]

  alias App.Model.Activity
  alias App.Model.Certificate
  alias App.Model.Chore
  alias App.Model.EquipmentItem
  alias App.Model.MemberCard
  alias App.Model.Standing
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.SaveCertificate
  alias App.Operation.SaveChore
  alias App.ViewData.EquipmentList
  alias App.ViewData.MemberMilestones
  alias App.ViewData.MemberRecords
  alias App.ViewData.MemberYear
  alias Service.Format
  alias Web.CertificateText
  alias Web.ChoreText
  alias Web.Components.MemberSidebar
  alias Web.QualificationText

  # Your membership (#406), /teams/:subdomain/me: a member's own page on one team. One
  # year of their activities (#576), this year unless `?year=` picks another, with its
  # hours as the tax credit letter counts them, and their qualifications and the
  # equipment they hold in the main column; their ID card, latest
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
      |> assign(:standing, Standing.today(member, team, now))
      |> assign_years(attended)
      |> assign(:chores, latest_chores(member))
      |> assign(:qualifications, MemberRecords.qualifications(member, now))
      |> assign(:certificates, sent_certificates(member))
      |> assign(:card, team.id_cards_enabled && MemberCard.find_current(team, member))
      |> assign(:letter, member |> TaxCreditLetter.get_all_for_member() |> List.first())
      |> assign(:milestones, MemberMilestones.for_member(member, now, attended))
      |> assign(:equipment, team |> EquipmentItem.held_by(member) |> EquipmentList.held_rows())

    {:ok, socket}
  end

  # When they last attended, for the header, and the years the menu offers.
  defp assign_years(socket, attended) do
    %{member: member, team: team, now: now} = socket.assigns

    assign(socket,
      any_activities?: attended != [],
      last_attended_at: attended |> List.first() |> then(&(&1 && &1.started_at)),
      years: MemberRecords.years_on_team(member, now),
      this_year: Service.YearRange.year_in(now, team.timezone)
    )
  end

  # The year's 10 latest, its activity count for the year page's link, and its hours.
  def handle_params(params, _uri, socket) do
    %{member: member, team: team, years: years, now: now} = socket.assigns
    year = year!(params["year"], years)
    rows = MemberRecords.attendances(member, year, now)

    {:noreply,
     assign(socket,
       year: year,
       activities: Enum.take(rows, 10),
       activity_count: MemberYear.activities(rows),
       hours: MemberYear.hours(rows, year, team.timezone, Activity.hours_tags(team))
     )}
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
      photo={~p"/teams/#{@team}/members/#{@member}/image"}
      standing={@standing}
      facts={facts(@member, @last_attended_at, @team.timezone)}
    />

    <div class="membership mt-6">
      <div class="min-w-0">
        <.activities
          team={@team}
          year={@year}
          this_year={@this_year}
          years={@years}
          activities={@activities}
          activity_count={@activity_count}
          any_activities?={@any_activities?}
          hours={@hours}
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
  attr :year, :integer, required: true
  attr :this_year, :integer, required: true
  attr :years, :list, required: true
  attr :activities, :list, required: true
  attr :activity_count, :integer, required: true
  attr :any_activities?, :boolean, required: true
  attr :hours, :map, required: true

  # Total first: it's the number people check. Primary and secondary are the letter's.
  defp activities(assigns) do
    ~H"""
    <section id="activities">
      <.heading_row>
        <h2 class="heading">Activities</h2>
        <:action><.year_menu years={@years} year={@year} class={nil} /></:action>
      </.heading_row>
      <div :if={@activities != []} id="year-stats" class="chart-stats">
        <.stat id="stat-total" value={Format.hours(@hours.total_minutes)} label="Total hours" />
        <.stat
          id="stat-primary"
          value={Format.hours(@hours.primary_minutes)}
          label="Primary hours"
        />
        <.stat
          id="stat-secondary"
          value={Format.hours(@hours.secondary_minutes)}
          label="Secondary hours"
        />
      </div>
      <.empty_state :if={!@any_activities?} id="no-activities" title="No activities yet">
        Activities you attend show here after SAR Duty refreshes.
        <:action>
          <p class="action">
            <.a id="coming-up-link" navigate={~p"/teams/#{@team}/activities"}>Activities coming up</.a>
          </p>
        </:action>
      </.empty_state>
      <.empty_state
        :if={@any_activities? and @activities == []}
        id="no-activities-in-year"
        title={"No activities in #{@year}"}
      >
        {if @year == @this_year,
          do: "Activities you attend show here after SAR Duty refreshes.",
          else: "Pick another year to see its activities."}
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
          navigate={~p"/teams/#{@team}/me/activities?year=#{@year}"}
        >All {Format.count(@activity_count, one: "1 activity", many: "%d activities")} in {@year}</.a>
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
          <span :if={chore.status == :declined} class="hint block mt-1">
            {ChoreText.declined(chore, @team.timezone)}
          </span>
        </:col>
        <:col :let={chore} label="" class="w-px whitespace-nowrap">
          <.status_badge chore={chore} />
          <.a
            :if={chore.status == :declined}
            id={"chore-delete-#{chore.id}"}
            href="#"
            phx-click="delete-chore"
            phx-value-id={chore.id}
            data-confirm={"Delete #{chore.description}?"}
          >Delete</.a>
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
        Qualifications your team records show here.
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
      >{CertificateText.title(@certificate)}</.a>
    <% else %>
      {CertificateText.title(@certificate)}
    <% end %>
    <span :if={@certificate.status == :waiting} class="hint block">
      Sent {Format.date_short(@certificate.inserted_at, @team.timezone)}. {if @certificate.qualification_id,
        do: "A team admin looks at it next.",
        else: "A team admin selects the qualification next."}
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
      data-confirm={CertificateText.delete_question(@certificate)}
    >Delete</.a>
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

  def handle_event("year", %{"year" => year}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/teams/#{socket.assigns.team}/me?year=#{year}")}

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

  def handle_event("delete-chore", %{"id" => id}, socket) do
    member = socket.assigns.member
    chore = Chore.find_for_member!(member, id)

    socket =
      case SaveChore.delete_own(member, chore) do
        :ok ->
          put_flash(socket, :info, "Deleted #{chore.description}.")

        {:error, :decided} ->
          put_flash(socket, :error, "This chore cannot be deleted. A team admin has accepted it.")
      end

    {:noreply, assign(socket, :chores, latest_chores(member))}
  end

  defp verify_label(card), do: "#{Web.VerifyHost.host()}/#{MemberCard.format_code(card.code)}"

  defp verify_url(card), do: "#{Web.VerifyHost.url()}/#{MemberCard.format_code(card.code)}"
end

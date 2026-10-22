defmodule Web.MeLive do
  use Web, {:live_view_app_layout, access: :member}

  import Web.Components.MemberLetter
  import Web.Components.MilestoneList

  alias App.Adapter.D4H
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.SaveOwnDetails
  alias App.ViewData.MemberRecords
  alias App.ViewData.Milestones
  alias Service.Format
  alias Web.QualificationText

  # Your membership (#406), /teams/:subdomain/me: a member's own page on one team. Their
  # activities this year and qualifications in the main column; their ID card, latest tax
  # credit letter, contact details, and milestones in a sidebar. `current_member` comes
  # from the login (Web.UserAuth, :ensure_team_access), never from the URL.
  def mount(_params, _session, socket) do
    member = socket.assigns.current_member
    team = member.team
    now = DateTime.utc_now()
    year = Service.YearRange.year_in(now, team.timezone)

    socket =
      socket
      |> assign(:page_title, member.name)
      |> assign(member: member, team: team, now: now, year: year)
      |> assign(:activities, member |> MemberRecords.attendances(year, now) |> Enum.take(10))
      |> assign(:qualifications, MemberRecords.qualifications(member, now))
      |> assign(:card, team.id_cards_enabled && MemberCard.find_current(team, member))
      |> assign(:letter, member |> TaxCreditLetter.get_all_for_member() |> List.first())
      |> assign(:milestones, member |> milestones(now) |> Enum.take(5))
      |> assign(:contacts?, "primary_emergency_contact" in SaveOwnDetails.fields(team))
      |> assign_emergency_contact()

    {:ok, socket}
  end

  defp milestones(member, now) do
    member
    |> MemberRecords.attended(now)
    |> Milestones.build(
      member.joined_at,
      MemberAwayPeriod.for_member(member),
      now,
      member.team.timezone
    )
  end

  # Emergency contacts are never copied (docs/members.md), so read from D4H after the
  # page shows, as Contact details does.
  defp assign_emergency_contact(%{assigns: %{contacts?: false}} = socket), do: socket

  defp assign_emergency_contact(socket) do
    member = socket.assigns.member

    assign_async(socket, :emergency_contact, fn ->
      case SaveOwnDetails.load(member) do
        {:ok, details} -> {:ok, %{emergency_contact: details.primary_emergency_contact}}
        {:error, text} -> {:error, text}
      end
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="person-head">
      <span class="avatar avatar-lg">
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
        <.activities team={@team} year={@year} activities={@activities} />
        <.qualifications team={@team} now={@now} qualifications={@qualifications} />
      </div>
      <aside class="membership-aside">
        <div :if={@team.id_cards_enabled or @letter} class="membership-aside-top">
          <section id="card-and-letter" class="card side-card">
            <.id_card :if={@team.id_cards_enabled} team={@team} card={@card} />
            <hr :if={@team.id_cards_enabled and @letter} />
            <.member_letter
              :if={@letter}
              id="letter"
              team={@team}
              letter={@letter}
              year={@letter.year}
            />
          </section>
        </div>
        <div class="membership-aside-bottom">
          <section id="details-and-milestones" class="card side-card">
            <.contact_details
              team={@team}
              member={@member}
              contacts?={@contacts?}
              emergency_contact={assigns[:emergency_contact]}
            />
            <hr />
            <.milestones milestones={@milestones} />
          </section>
        </div>
      </aside>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :year, :integer, required: true
  attr :activities, :list, required: true

  defp activities(assigns) do
    ~H"""
    <section id="activities">
      <h2 class="heading">Activities in {@year}</h2>
      <.empty_state :if={@activities == []} id="no-activities" title={"No activities in #{@year} yet"}>
        Activities you attend show here after SAR Duty refreshes from {D4H.service_name(@team)}.
      </.empty_state>
      <.table
        :if={@activities != []}
        id="activities-list"
        rows={@activities}
        row_id={&"activities-list-#{&1.id}"}
      >
        <:col :let={attendance} label="Date" class="w-px whitespace-nowrap">
          {day(attendance.started_at, @team.timezone)}
        </:col>
        <:col :let={attendance} label="Activity">
          <.d4h_activity_link team={@team} activity={attendance.activity} />
        </:col>
        <:col :let={attendance} label="Kind" class="w-px whitespace-nowrap max-md:hidden">
          <.activity_kind_mark activity={attendance.activity} />
        </:col>
        <:col :let={attendance} label="Time" align="right" class="w-px whitespace-nowrap">
          {Format.duration(MemberRecords.minutes(attendance))}
        </:col>
      </.table>
      <p :if={@activities != []} class="mt-2">
        <.a id="all-activities" navigate={~p"/teams/#{@team}/me/activities?year=#{@year}"}>
          All your activities in {@year}
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
  attr :contacts?, :boolean, required: true
  attr :emergency_contact, :any, default: nil

  defp contact_details(assigns) do
    ~H"""
    <div id="contact-details">
      <h2 class="chart-title mb-1">Contact details</h2>
      <dl class="mb-3">
        <dt>Mobile</dt>
        <dd id="contact-mobile">{@member.phone || "None"}</dd>
        <dt>Address</dt>
        <dd id="contact-address">{@member.address || "None"}</dd>
        <%= if @contacts? do %>
          <dt>Emergency contact</dt>
          <dd id="contact-emergency">
            <.async_result :let={contact} assign={@emergency_contact}>
              <:loading><span class="hint">Reading {D4H.service_name(@team)}…</span></:loading>
              <:failed :let={_failure}>
                <span class="hint">SAR Duty cannot reach {D4H.service_name(@team)}.</span>
              </:failed>
              {contact_line(contact)}
            </.async_result>
          </dd>
        <% end %>
      </dl>
      <p class="mb-0">
        <.a id="change-details" navigate={~p"/teams/#{@team}/me/details"}>
          Change contact details
        </.a>
      </p>
    </div>
    """
  end

  attr :milestones, :list, required: true

  defp milestones(assigns) do
    ~H"""
    <div id="milestones">
      <h2 class="chart-title mb-1">Milestones</h2>
      <p :if={@milestones == []} id="no-milestones" class="hint mb-0">
        No milestones yet. The first comes with your first incident, 100 hours, or 1 year on
        the team.
      </p>
      <.milestone_list :if={@milestones != []} id="milestones-list" milestones={@milestones} />
    </div>
    """
  end

  # "Jo Rivera · 604-555-0101", or None when D4H has no contact.
  defp contact_line(%{"name" => name} = contact) when is_binary(name),
    do: [name, contact["primary_phone"]] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ")

  defp contact_line(_contact), do: "None"

  # "Oct 15": the year is in the heading.
  defp day(started_at, timezone) do
    {date, _time} = Service.Convert.utc_to_local(started_at, timezone)
    Format.day_in_year(date, date)
  end

  defp verify_label(card), do: "#{Web.VerifyHost.host()}/#{MemberCard.format_code(card.code)}"

  defp verify_url(card), do: "#{Web.VerifyHost.url()}/#{MemberCard.format_code(card.code)}"
end

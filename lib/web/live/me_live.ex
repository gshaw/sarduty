defmodule Web.MeLive do
  use Web, :live_view_app_layout

  import Web.Components.ViewSwitch

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.ViewData.MemberRecords
  alias Web.QualificationText

  # A member's own page (#156), /teams/:subdomain/me: their ID card, tax credit letters,
  # qualifications, the activities they're signed up for, and hours and activities for a
  # year (`?year=`). `member` comes from
  # the login (Web.UserAuth, :ensure_team_member), never from the URL. Mostly read on a
  # phone.
  def mount(_params, _session, socket) do
    member = socket.assigns.member
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(:page_title, member.team.name)
      |> assign(:now, now)
      |> assign(:card, MemberCard.find_current(member.team, member))
      |> assign(:letters, TaxCreditLetter.get_all_for_member(member))
      |> assign(:years, MemberRecords.years(member, now))
      |> assign(:qualifications, MemberRecords.qualifications(member, now))
      |> assign(:signed_up, MemberRecords.signed_up(member, now))
      |> assign(:hours_tags, Activity.hours_tags(member.team))

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    %{member: member, years: years} = socket.assigns
    year = parse_year(params["year"], years)
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(:year, year)
      |> assign(:hours, MemberRecords.hours(member, year, now))
      |> assign(:attendances, MemberRecords.attendances(member, year, now))

    {:noreply, socket}
  end

  defp parse_year(nil, [this_year | _older]), do: this_year

  defp parse_year(param, years) do
    case Integer.parse(param) do
      {year, ""} -> if year in years, do: year, else: raise(Web.Status.NotFound)
      _other -> raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">{@member.team.name}</h1>
      <p class="lead">{@member.name}</p>

      <%= if @card || @member.team.id_cards_enabled do %>
        <h2 class="heading mt-8">ID card</h2>
        <.card_content card={@card} member={@member} />
      <% end %>

      <h2 class="heading mt-8">Tax credit letters</h2>
      <.empty_state :if={@letters == []} id="no-letters" title="No tax credit letters yet">
        Your team admins make them after each year ends.
      </.empty_state>
      <ul :if={@letters != []} id="letters" class="flex flex-col gap-4">
        <li :for={letter <- @letters} id={"letter-#{letter.id}"}>
          <.button href={~p"/teams/#{@member.team}/me/tax-credit-letters/#{letter.id}/pdf"}>
            Download {letter.year} letter
          </.button>
          <span class="hint block mt-1">
            Made {Service.Format.date_long(letter.inserted_at, @member.team.timezone)}
          </span>
        </li>
      </ul>

      <h2 class="heading mt-8">Qualifications</h2>
      <.qualifications_content qualifications={@qualifications} member={@member} now={@now} />

      <h2 :if={@signed_up != []} class="heading mt-8">Signed up for</h2>
      <.signed_up_content :if={@signed_up != []} signed_up={@signed_up} member={@member} />

      <div class="heading-row mt-8">
        <h2 class="heading">Hours in {@year}</h2>
        <.view_switch :if={length(@years) > 1} id="years" label="Year">
          <:view
            :for={year <- @years}
            id={"year-#{year}"}
            patch={~p"/teams/#{@member.team}/me?year=#{year}"}
            current={year == @year}
          >
            {year}
          </:view>
        </.view_switch>
      </div>
      <.hours_content hours={@hours} hours_tags={@hours_tags} />
      <.attendance_content attendances={@attendances} year={@year} member={@member} />
    </div>
    """
  end

  defp hours_content(assigns) do
    ~H"""
    <dl id="hours">
      <dt>Primary hours</dt>
      <dd id="hours-primary">{format_minutes(@hours.primary_minutes)}</dd>
      <dt>Secondary hours</dt>
      <dd id="hours-secondary">{format_minutes(@hours.secondary_minutes)}</dd>
      <dt>Total</dt>
      <dd id="hours-total">{format_minutes(@hours.total_minutes)}</dd>
    </dl>
    <p class="hint">
      Counted the same way as your tax credit letter. Only activities with the {@hours_tags.primary} or {@hours_tags.secondary} tag count.
    </p>
    """
  end

  defp signed_up_content(assigns) do
    ~H"""
    <.table id="signed-up" rows={@signed_up} row_id={&"signed-up-#{&1.id}"}>
      <:col :let={attendance} label="Date" class="w-px whitespace-nowrap">
        {Service.Format.date_short(attendance.started_at, @member.team.timezone)}
      </:col>
      <:col :let={attendance} label="Activity">
        <.d4h_activity_link team={@member.team} activity={attendance.activity} />
      </:col>
      <:col :let={attendance} label="Kind" class="w-px whitespace-nowrap">
        <.activity_kind_mark activity={attendance.activity} />
      </:col>
    </.table>
    <p class="hint">Hours count once the activity starts.</p>
    """
  end

  defp attendance_content(%{attendances: []} = assigns) do
    ~H"""
    <.empty_state id="no-attendance" title={"No activities in #{@year}"}>
      Activities you attended show here after SAR Duty refreshes from {D4H.service_name(@member.team)}.
    </.empty_state>
    """
  end

  defp attendance_content(assigns) do
    ~H"""
    <p class="mt-6">
      {Service.Format.count(length(@attendances), one: "1 activity", many: "%d activities")} attended.
      Missing one? Tell a team admin, who can fix it in {D4H.service_name(@member.team)}.
    </p>
    <.table
      id="attendance"
      rows={@attendances}
      row_id={&"attendance-#{&1.id}"}
    >
      <:col :let={attendance} label="Date" class="w-px whitespace-nowrap">
        {Service.Format.date_short(attendance.started_at, @member.team.timezone)}
      </:col>
      <:col :let={attendance} label="Activity">
        <.d4h_activity_link team={@member.team} activity={attendance.activity} />
      </:col>
      <:col :let={attendance} label="Kind" class="w-px whitespace-nowrap">
        <.activity_kind_mark activity={attendance.activity} />
      </:col>
      <:col :let={attendance} label="Time" align="right" class="w-px whitespace-nowrap">
        {format_minutes(MemberRecords.minutes(attendance))}
      </:col>
    </.table>
    """
  end

  defp qualifications_content(%{qualifications: []} = assigns) do
    ~H"""
    <.empty_state id="no-qualifications" title="No qualifications">
      Qualifications you hold in {D4H.service_name(@member.team)} show here.
    </.empty_state>
    """
  end

  defp qualifications_content(assigns) do
    assigns = assign(assigns, :expiring, MemberRecords.expiring(assigns.qualifications))

    ~H"""
    <.banner
      :if={@expiring != []}
      id="qualifications-expiring"
      kind={:warning}
      title={QualificationText.expiring_title(@expiring)}
    >
      <p :for={row <- @expiring}>{QualificationText.expiring_line(row, @member.team.timezone)}</p>
      <p>{QualificationText.renew_line(@expiring)}</p>
    </.banner>
    <.table
      id="qualifications"
      rows={@qualifications}
      row_id={&"qualifications-#{&1.award.qualification_id}"}
      row_class={&QualificationText.row_class/1}
    >
      <:col :let={row} label="Qualification">{row.award.qualification.title}</:col>
      <:col :let={row} label="Expires" class="w-px whitespace-nowrap">
        {QualificationText.expires(row.award, @now, @member.team.timezone)}
        <.badge :if={row.status == :expiring} kind={:warning}>
          {QualificationText.days_left(row)}
        </.badge>
      </:col>
      <:col :let={row} label="First held" class="w-px whitespace-nowrap">
        {QualificationText.first_held(row, @member.team.timezone)}
      </:col>
    </.table>
    """
  end

  defp format_minutes(minutes), do: Service.Format.duration(minutes)

  defp card_content(%{card: nil} = assigns) do
    ~H"""
    <p id="no-card">You do not have an ID card yet. Ask a team admin to issue one.</p>
    """
  end

  defp card_content(assigns) do
    ~H"""
    <div id="card">
      <dl>
        <dt>Code</dt>
        <dd id="card-code" class="mono text-lg">{MemberCard.format_code(@card.code)}</dd>
        <dt>Issued</dt>
        <dd>{Service.Format.date_long(@card.inserted_at, @member.team.timezone)}</dd>
      </dl>
      <.form_actions :if={BuildApplePass.configured?() or BuildGooglePass.configured?()}>
        <.button
          :if={BuildApplePass.configured?()}
          id="apple-pass"
          variant={:primary}
          href={~p"/teams/#{@member.team}/me/card/apple-wallet"}
        >
          Add to Apple Wallet
        </.button>
        <.button
          :if={BuildGooglePass.configured?()}
          id="google-pass"
          variant={:primary}
          href={~p"/teams/#{@member.team}/me/card/google-wallet"}
        >
          Add to Google Wallet
        </.button>
      </.form_actions>
      <p class="hint">
        Anyone can verify your ID card at <.a id="card-verify-link" href={verify_url(@card)}>{verify_label(@card)}</.a>.
      </p>
    </div>
    """
  end

  defp verify_label(card), do: "#{Web.VerifyHost.host()}/#{MemberCard.format_code(card.code)}"

  defp verify_url(card), do: "#{Web.VerifyHost.url()}/#{MemberCard.format_code(card.code)}"
end

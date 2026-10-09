defmodule Web.MeLive do
  use Web, :live_view_narrow_layout

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.IssueMemberCard
  alias App.ViewData.MemberRecords

  # A member's own page (#156), /teams/:subdomain/me: their ID card, tax credit letters,
  # hours and activities for a year (`?year=`), and qualifications. `member` comes from
  # the login (Web.UserAuth, :ensure_team_member), never from the URL. Mostly read on a
  # phone.
  def mount(_params, _session, socket) do
    member = socket.assigns.member
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(:page_title, member.team.name)
      |> assign(:card, MemberCard.find_current(member.team, member))
      |> assign(:letters, TaxCreditLetter.get_all_for_member(member))
      |> assign(:years, MemberRecords.years(member, now))
      |> assign(:qualifications, MemberRecords.qualifications(member, now))

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    %{member: member, years: years} = socket.assigns
    year = parse_year(params["year"], years)

    socket =
      socket
      |> assign(:year, year)
      |> assign(:hours, MemberRecords.hours(member, year))
      |> assign(:attendances, MemberRecords.attendances(member, year))

    {:noreply, socket}
  end

  defp parse_year(nil, [this_year | _older]), do: this_year

  defp parse_year(param, years) do
    case Integer.parse(param) do
      {year, ""} -> if year in years, do: year, else: raise(Web.Status.NotFound)
      _other -> raise Web.Status.NotFound
    end
  end

  # The member gets a card only when they have none, so a second tap can't cancel the
  # one just added to Wallet. The login is checked again, in case the team turned member
  # logins off since the page opened.
  def handle_event("issue", _params, socket) do
    %{current_user: user, member: member} = socket.assigns

    case Member.get_login(user.email, member.id, DateTime.utc_now()) do
      nil ->
        {:noreply, redirect(socket, to: ~p"/")}

      member ->
        card =
          case MemberCard.find_current(member.team, member) do
            nil ->
              {:ok, card} = IssueMemberCard.call(member.team, member, DateTime.utc_now())
              card

            card ->
              card
          end

        {:noreply, socket |> assign(:card, card) |> put_flash(:info, "Your ID card is ready.")}
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">{@member.team.name}</h1>
      <p class="lead">{@member.name}</p>

      <h2 class="subheading mt-8">ID card</h2>
      <.card_content card={@card} member={@member} />

      <ul class="row-links mt-6">
        <li>
          <.row_link id="contact-link" navigate={~p"/teams/#{@member.team}/me/contact"}>
            <span class="text-link">Your email and mobile number</span>
            <span class="hint block">What you log in with</span>
          </.row_link>
        </li>
        <li>
          <.row_link id="details-link" navigate={~p"/teams/#{@member.team}/me/details"}>
            <span class="text-link">Your contact details</span>
            <span class="hint block">
              {if App.Adapter.D4H.records?(@member.team),
                do: "Your mailing address",
                else: "Your mailing address and emergency contacts"}
            </span>
          </.row_link>
        </li>
      </ul>

      <h2 class="subheading mt-8">Tax credit letters</h2>
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

      <h2 class="subheading mt-8">Qualifications</h2>
      <.qualifications_content qualifications={@qualifications} member={@member} />

      <div class="heading-row mt-8">
        <h2 class="subheading">Hours in {@year}</h2>
        <nav :if={length(@years) > 1} id="years" aria-label="Year" class="flex gap-3">
          <.link
            :for={year <- @years}
            id={"year-#{year}"}
            patch={~p"/teams/#{@member.team}/me?year=#{year}"}
            aria-current={year == @year && "page"}
            class={["link", year == @year && "font-semibold"]}
          >
            {year}
          </.link>
        </nav>
      </div>
      <.hours_content hours={@hours} />
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
      Counted the same way as your tax credit letter. Only activities with the Primary Hours or
      Secondary Hours tag count.
    </p>
    """
  end

  defp attendance_content(%{attendances: []} = assigns) do
    ~H"""
    <.empty_state id="no-attendance" title={"No activities in #{@year}"}>
      Activities you attended show here after SAR Duty refreshes from D4H.
    </.empty_state>
    """
  end

  defp attendance_content(assigns) do
    ~H"""
    <p class="mt-6">
      {Service.Format.count(length(@attendances), one: "1 activity", many: "%d activities")} attended.
      Missing one? Tell a team admin, who can fix it in D4H.
    </p>
    <ul id="attendance" class="flex flex-col">
      <li
        :for={attendance <- @attendances}
        id={"attendance-#{attendance.id}"}
        class="py-2 border-b border-border-subtle"
      >
        <span class="block">{attendance.activity.title}</span>
        <span class="hint block">
          {Service.Format.date_long(attendance.started_at, @member.team.timezone)} ·
          <span class={["activity-kind", "activity-kind-#{attendance.activity.activity_kind}"]}>
            {String.capitalize(attendance.activity.activity_kind)}
          </span>
          · {format_minutes(MemberRecords.minutes(attendance))}
        </span>
      </li>
    </ul>
    """
  end

  defp qualifications_content(%{qualifications: %{current: [], expired: []}} = assigns) do
    ~H"""
    <.empty_state id="no-qualifications" title="No qualifications">
      Qualifications you hold in {App.Adapter.D4H.service_name(@member.team)} show here.
    </.empty_state>
    """
  end

  defp qualifications_content(assigns) do
    ~H"""
    <ul :if={@qualifications.current != []} id="qualifications" class="flex flex-col">
      <li
        :for={%{award: award, expiring?: expiring?} <- @qualifications.current}
        id={"qualification-#{award.qualification_id}"}
        class="py-2 border-b border-border-subtle"
      >
        <span class="block">
          {award.qualification.title}
          <.badge :if={expiring?} kind={:warning}>Expires soon</.badge>
        </span>
        <span class="hint block">{expiry(award, @member.team.timezone)}</span>
      </li>
    </ul>
    <h3 :if={@qualifications.expired != []} class="font-semibold mt-6">Expired</h3>
    <ul :if={@qualifications.expired != []} id="expired-qualifications" class="flex flex-col">
      <li
        :for={%{award: award} <- @qualifications.expired}
        id={"qualification-#{award.qualification_id}"}
        class="py-2 border-b border-border-subtle"
      >
        <span class="block">{award.qualification.title}</span>
        <span class="hint block">
          Expired {Service.Format.date_long(award.ends_at, @member.team.timezone)}
        </span>
      </li>
    </ul>
    """
  end

  defp expiry(%{ends_at: nil}, _timezone), do: "Does not expire"

  defp expiry(%{ends_at: ends_at}, timezone),
    do: "Expires #{Service.Format.date_long(ends_at, timezone)}"

  defp format_minutes(minutes), do: Service.Format.duration_as_hours_minutes_medium(minutes)

  defp card_content(%{card: nil} = assigns) do
    ~H"""
    <div id="no-card">
      <p>You do not have an ID card yet. Get one, then add it to your phone's Wallet.</p>
      <.form_actions>
        <.button id="issue" variant={:primary} phx-click="issue" phx-disable-with="Making card…">
          Get ID card
        </.button>
      </.form_actions>
    </div>
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

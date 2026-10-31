defmodule Web.MemberCardLive do
  use Web, :live_view_app_layout

  import Web.Components.MemberPage
  import Web.Components.MemberSidebar, only: [load_sidebar: 1]

  alias App.Model.Endorsement
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildCardQualifications
  alias App.Operation.BuildGooglePass
  alias App.Operation.EmailMemberCard
  alias App.Operation.IssueMemberCard
  alias App.Operation.RevokeMemberCard
  alias App.Repo

  # A phone fetching the pass ticks "last fetched" over. The topic is by the URL's member
  # id, but the message carries nothing; the card is looked up through the team.
  def mount(params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(App.PubSub, MemberCard.pass_topic(params["id"]))

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    member = team |> Member.find!(params["id"]) |> Repo.preload([:team])
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(:page_title, "#{member.name} · ID card")
      |> assign(:member, member)
      |> assign(:current?, Member.current?(member, now))
      |> load_sidebar()
      |> assign_card(MemberCard.find_current(team, member))
      |> assign(:qualifications, BuildCardQualifications.call(team, member, now))
      |> assign(:endorsements_on_card?, Endorsement.any_on_card?(team.id))

    {:noreply, socket}
  end

  # The page shows the new card, so no message.
  def handle_event("issue", _params, socket) do
    %{current_team: team, member: member} = socket.assigns

    case IssueMemberCard.call(team, member, DateTime.utc_now()) do
      {:ok, card} -> {:noreply, assign_card(socket, card)}
      {:error, :id_cards_off} -> {:noreply, put_flash(socket, :error, id_cards_off(team))}
      {:error, :retired} -> {:noreply, socket}
    end
  end

  def handle_event("email", _params, socket) do
    %{current_team: team, member: member} = socket.assigns

    socket =
      case EmailMemberCard.call(team, member, DateTime.utc_now()) do
        :ok -> put_flash(socket, :info, "Emailed the ID card to #{member.email}.")
        {:error, :no_email} -> put_flash(socket, :error, "#{member.name} has no email.")
        {:error, _reason} -> put_flash(socket, :error, "The email did not send. Try again.")
      end

    {:noreply, socket}
  end

  # The page shows the card is gone, so no message.
  def handle_event("revoke", _params, socket) do
    %{current_team: team, member: member} = socket.assigns
    :ok = RevokeMemberCard.call(team, member, DateTime.utc_now())
    {:noreply, assign_card(socket, nil)}
  end

  def handle_info(:pass_fetched, socket) do
    %{current_team: team, member: member} = socket.assigns
    {:noreply, assign_card(socket, MemberCard.find_current(team, member))}
  end

  # Swoosh's test adapter sends each email to the process that sent it.
  def handle_info(_message, socket), do: {:noreply, socket}

  # Once a team is in an organization, its organization admins turn cards on (#512).
  defp id_cards_off(%{organization_id: nil}),
    do: "A SAR Duty site admin turns them on after checking your team. Ask one to turn them on."

  defp id_cards_off(_team), do: "Your organization admins turn them on. Ask one to turn them on."

  defp assign_card(socket, card) do
    phones = if card, do: length(PassRegistration.get_all_for_serial(card)), else: 0
    socket |> assign(:card, card) |> assign(:phones, phones)
  end

  defp wallet?, do: BuildApplePass.configured?() or BuildGooglePass.configured?()

  def render(assigns) do
    ~H"""
    <.member_page
      current_member={@current_member}
      member={@member}
      tab={:card}
      last_attended_at={@last_attended_at}
      standing={@standing}
      milestones={@milestones}
      equipment={@equipment}
      fields?={@fields?}
      maps_app={@current_user.maps_app}
      team_admin?={@team_admin?}
    >
      <.banner
        :if={!@current_team.id_cards_enabled}
        id="id-cards-off"
        kind={:danger}
        title="ID cards are off"
      >
        {id_cards_off(@current_team)}
      </.banner>
      <.card_content
        :if={@current_team.id_cards_enabled}
        card={@card}
        member={@member}
        current?={@current?}
        qualifications={@qualifications}
        endorsements_on_card?={@endorsements_on_card?}
        phones={@phones}
        member_logins?={@current_team.member_logins}
        service={@service}
      />
    </.member_page>
    """
  end

  defp card_content(%{card: nil, current?: false} = assigns) do
    ~H"""
    <p id="no-card">{@member.name} is retired, so they cannot get an ID card.</p>
    """
  end

  defp card_content(%{card: nil} = assigns) do
    ~H"""
    <div id="no-card">
      <p>{@member.name} has no ID card.</p>
      <.button id="issue" variant={:primary} phx-click="issue">Issue ID card</.button>
    </div>
    """
  end

  defp card_content(assigns) do
    ~H"""
    <div id="card">
      <dl>
        <dt>Code</dt>
        <dd class="mono">
          <.a id="card-verify-link" href={verify_url(@card)}>{Web.VerifyHost.host()}/<span id="card-code">{MemberCard.format_code(
            @card.code
          )}</span></.a>
        </dd>
        <dt>Status</dt>
        <dd id="card-status">
          {if @current?, do: "Active", else: "Not active: #{@member.name} is retired"}
        </dd>
        <dt>Issued</dt>
        <dd>{Service.Format.date_short(@card.inserted_at, @member.team.timezone)}</dd>
        <dt>Endorsements</dt>
        <dd id="card-qualifications">
          <div :for={q <- @qualifications}>
            {BuildCardQualifications.describe(q, @member.team.timezone)}
          </div>
          <div :if={@qualifications == [] and @endorsements_on_card?}>None</div>
          <div :if={!@endorsements_on_card?}>
            Your team shows no endorsements on ID cards.
            <.a navigate={~p"/teams/#{@member.team}/endorsements"}>Select endorsements to show</.a>
          </div>
        </dd>
        <dt :if={wallet?()}>Wallet</dt>
        <dd :if={wallet?()}>
          <span id="card-phones">{wallet_status(@phones, @card, @member.team.timezone)}</span>
        </dd>
      </dl>
      <.form_actions>
        <.button
          :if={@current? && @member.email && wallet?()}
          id="email-pass"
          variant={:primary}
          phx-click="email"
          phx-disable-with="Sending…"
          data-confirm={"Email the ID card to #{@member.email}?"}
        >
          Email ID card
        </.button>
        <:trailing>
          <.button
            id="revoke"
            variant={:danger}
            phx-click="revoke"
            data-confirm={"Cancel #{@member.name}'s ID card? Its code stops working, and Wallet shows it as cancelled."}
          >
            Cancel ID card
          </.button>
        </:trailing>
      </.form_actions>
      <p :if={@current? and wallet?()} id="card-delivery" class="hint">
        {delivery_hint(assigns)}
      </p>
    </div>
    """
  end

  # How the card reaches the member's phone, now that only they add it to Wallet.
  defp delivery_hint(%{member_logins?: true, member: member}),
    do: "#{member.name} adds it to Wallet from Your membership."

  defp delivery_hint(%{member: %{email: nil} = member, service: service}),
    do: "#{member.name} has no email. Add one in #{service} to email the ID card."

  defp delivery_hint(%{member: member}),
    do: "Email it so #{member.name} can add it to Wallet."

  defp wallet_status(phones, card, timezone) do
    google = if card.in_wallet_at, do: "In Google Wallet"

    case [apple_status(phones, card, timezone), google] |> Enum.reject(&is_nil/1) do
      [] -> "Not in Wallet yet"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp apple_status(0, _card, _timezone), do: nil

  defp apple_status(phones, card, timezone) do
    on = "In Apple Wallet on #{Service.Format.count(phones, one: "1 phone", many: "%d phones")}"

    case card.pass_fetched_at do
      nil ->
        on

      fetched_at ->
        "#{on} · last downloaded #{Service.Format.month_day_time(fetched_at, timezone)}"
    end
  end

  # The card's page on the verify site, the same one its QR code opens.
  defp verify_url(card), do: "#{Web.VerifyHost.url()}/#{MemberCard.format_code(card.code)}"
end

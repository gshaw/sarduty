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
  alias App.Operation.SendMemberCard
  alias App.Repo

  # A phone fetching the pass, or the card's job making it or emailing it, ticks the tab
  # over. The topic is by the URL's member id, but the message carries nothing; the card
  # is looked up through the team.
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
      |> assign(:active?, Member.good_standing?(member, now))
      |> load_sidebar()
      |> assign_card(MemberCard.find_current(team, member))
      |> assign(:qualifications, BuildCardQualifications.call(team, member, now))
      |> assign(:endorsements_on_card?, Endorsement.any_on_card?(team.id))

    {:noreply, socket}
  end

  # Issue ID card, or Replace ID card once there is one: a new code, and its email
  # queued. The page shows the new card and its Emailed row, so no message.
  def handle_event("issue", _params, socket) do
    %{current_team: team, member: member} = socket.assigns

    case SendMemberCard.issue(team, member, DateTime.utc_now()) do
      {:ok, _card} -> {:noreply, reload_card(socket)}
      {:error, :id_cards_off} -> {:noreply, put_flash(socket, :error, id_cards_off(team))}
      {:error, :not_active} -> {:noreply, socket}
    end
  end

  def handle_event("email", _params, socket) do
    %{current_team: team, member: member} = socket.assigns

    socket =
      case SendMemberCard.email(team, member, DateTime.utc_now()) do
        {:ok, _card} -> put_flash(socket, :info, "Sending the ID card to #{member.email}.")
        {:error, :no_email} -> put_flash(socket, :error, "#{member.name} has no email.")
        {:error, :no_card} -> socket
      end

    {:noreply, reload_card(socket)}
  end

  def handle_info(message, socket)
      when message in [:pass_fetched, :wallet_changed, :card_changed],
      do: {:noreply, reload_card(socket)}

  # Swoosh's test adapter sends each email to the process that sent it.
  def handle_info(_message, socket), do: {:noreply, socket}

  # Once a team is in an organization, its organization admins turn cards on (#512).
  defp id_cards_off(%{organization_id: nil}),
    do: "A SAR Duty site admin turns them on after checking your team. Ask one to turn them on."

  defp id_cards_off(_team), do: "Your organization admins turn them on. Ask one to turn them on."

  defp reload_card(socket) do
    %{current_team: team, member: member} = socket.assigns
    assign_card(socket, MemberCard.find_current(team, member))
  end

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
        active?={@active?}
        standing={@standing}
        qualifications={@qualifications}
        endorsements_on_card?={@endorsements_on_card?}
        phones={@phones}
        member_logins?={@current_team.member_logins}
        service={@service}
      />
    </.member_page>
    """
  end

  defp card_content(%{card: nil, active?: false} = assigns) do
    ~H"""
    <p id="no-card">{@member.name} is {not_active_text(@standing)}, so they cannot get an ID card.</p>
    """
  end

  defp card_content(%{card: nil} = assigns) do
    ~H"""
    <div id="no-card">
      <p>{@member.name} has no ID card.</p>
      <.button id="issue" variant={:primary} phx-click="issue" phx-disable-with="Issuing…">
        Issue ID card
      </.button>
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
          {if @active?,
            do: "Active",
            else: "Not active: #{@member.name} is #{not_active_text(@standing)}"}
        </dd>
        <dt>Issued</dt>
        <dd>{Service.Format.date_short(@card.inserted_at, @member.team.timezone)}</dd>
        <dt :if={@card.email_status}>Emailed</dt>
        <dd :if={@card.email_status} id="card-emailed">
          {emailed_text(@card, @member)}
        </dd>
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
          <span id="card-phones">{Web.WalletText.summary(@phones, @card, @member.team.timezone)}</span>
        </dd>
      </dl>
      <.form_actions :if={@active?}>
        <.button
          :if={@member.email && wallet?()}
          id="email-pass"
          variant={:primary}
          phx-click="email"
          phx-disable-with="Sending…"
          data-confirm={"Email the ID card to #{@member.email}?"}
        >
          Email ID card
        </.button>
        <.button
          id="replace"
          phx-click="issue"
          phx-disable-with="Replacing…"
          data-confirm={replace_confirm(@member)}
        >
          Replace ID card
        </.button>
      </.form_actions>
      <p :if={@active? and wallet?()} id="card-delivery" class="hint">
        {delivery_hint(assigns)}
      </p>
    </div>
    """
  end

  # Why a member's card is not active, or why they cannot get one.
  defp not_active_text(:retiring), do: "retiring"
  defp not_active_text(_standing), do: "retired"

  defp replace_confirm(%Member{email: email} = member) when email not in [nil, ""],
    do:
      "Replace #{member.name}'s ID card? Its code stops working. The new card is emailed to #{email}."

  defp replace_confirm(member), do: "Replace #{member.name}'s ID card? Its code stops working."

  defp emailed_text(%MemberCard{email_status: :sending}, member), do: "Sending to #{member.email}"

  defp emailed_text(%MemberCard{email_status: :sent} = card, member),
    do: "#{Service.Format.date_short(card.emailed_at, member.team.timezone)}, to #{member.email}"

  defp emailed_text(%MemberCard{email_status: :failed}, %Member{email: email} = member)
       when email in [nil, ""],
       do: "Not sent: #{member.name} has no email."

  defp emailed_text(%MemberCard{email_status: :failed}, _member),
    do: "Did not send. Select Email ID card to try again."

  # How the card reaches the member's phone, now that only they add it to Wallet.
  defp delivery_hint(%{member_logins?: true, member: member}),
    do: "#{member.name} adds it to Wallet from Your membership."

  defp delivery_hint(%{member: %{email: nil} = member, service: service}),
    do: "#{member.name} has no email. Add one in #{service} to email the ID card."

  defp delivery_hint(%{member: member}),
    do: "Email it so #{member.name} can add it to Wallet."

  # The card's page on the verify site, the same one its QR code opens.
  defp verify_url(card), do: "#{Web.VerifyHost.url()}/#{MemberCard.format_code(card.code)}"
end

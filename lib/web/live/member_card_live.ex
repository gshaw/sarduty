defmodule Web.MemberCardLive do
  use Web, :live_view_app_layout

  import Web.Components.MemberPage
  import Web.Components.MemberSidebar, only: [load_sidebar: 1]

  alias App.Model.Endorsement
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Model.Team
  alias App.Operation.AskForPhoto
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildCardQualifications
  alias App.Operation.BuildGooglePass
  alias App.Operation.CancelMemberCard
  alias App.Operation.CheckMemberPhoto
  alias App.Operation.IssueMemberCard
  alias App.Operation.RefreshMemberCard
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
      |> assign_member(member)
      |> load_sidebar()
      |> assign_card(MemberCard.find_current(team, member))
      |> assign(:qualifications, BuildCardQualifications.call(team, member, now))
      |> assign(:endorsements_on_card?, Endorsement.any_on_card?(team.id))
      # The member's open ask for a photo (#1030), so two team admins do not both ask.
      |> assign(:ask, AskForPhoto.open_for(team, member, now))

    {:noreply, socket}
  end

  # Issue ID card, for a member with no card: a new code, and its email queued. The page
  # shows the new card and its Emailed row, so no message. The photo is checked live
  # first, so one added a minute ago counts (#1012).
  def handle_event("issue", _params, socket) do
    %{current_team: team, member: member} = socket.assigns
    member = CheckMemberPhoto.call(member)
    socket = assign_member(socket, member)

    case SendMemberCard.issue(team, member, DateTime.utc_now()) do
      {:ok, _card} -> {:noreply, reload_card(socket)}
      {:error, :id_cards_off} -> {:noreply, put_flash(socket, :error, id_cards_off(team))}
      {:error, :no_photo} -> {:noreply, put_flash(socket, :error, no_photo(member))}
      {:error, :not_active} -> {:noreply, socket}
    end
  end

  # Refresh ID card (#1012): the phones holding the card download it again, with the
  # photo, name, and standing as the team's records have them now.
  def handle_event("refresh", _params, socket) do
    %{current_team: team, member: member} = socket.assigns

    socket =
      case RefreshMemberCard.call(team, member, DateTime.utc_now()) do
        {:ok, _card} ->
          put_flash(
            socket,
            :info,
            "#{member.name}'s ID card refreshed. Phones that hold it get it within a minute."
          )

        {:error, :no_card} ->
          socket
      end

    {:noreply, reload_card(socket)}
  end

  # Cancel ID card (#964, #1012), for any card. A lost phone takes Cancel, then Issue ID
  # card, which the tab shows next.
  def handle_event("cancel", _params, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    socket =
      case CancelMemberCard.call(team, member, user, DateTime.utc_now()) do
        {:ok, _cards} -> put_flash(socket, :info, "#{member.name}'s ID card cancelled.")
        {:error, :no_card} -> socket
      end

    {:noreply, reload_card(socket)}
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

  # No words name D4H or Records, so one sentence fits both kinds of team.
  defp no_photo(member), do: "#{member.name} has no photo. Add one, then try again."

  # The member, and whether they are in good standing.
  defp assign_member(socket, member),
    do: assign(socket, member: member, active?: Member.good_standing?(member, DateTime.utc_now()))

  defp reload_card(socket) do
    %{current_team: team, member: member} = socket.assigns
    assign_card(socket, MemberCard.find_current(team, member))
  end

  defp assign_card(socket, card) do
    %{current_team: team, member: member} = socket.assigns
    phones = if card, do: PassRegistration.count_holding(card), else: 0
    revoked_at = if !card, do: MemberCard.last_revoked_at(team, member)

    assign(socket,
      card: card,
      phones: phones,
      revoked_at: revoked_at,
      image_path: card && card_image_path(card)
    )
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
        image_path={@image_path}
        revoked_at={@revoked_at}
        every_member_card?={@current_team.every_member_card}
        member_logins?={@current_team.member_logins}
        photos?={Team.photos?(@current_team)}
        service={@service}
      />
      <.add_photo
        :if={!@current_team.id_cards_enabled and Team.photos?(@current_team) and !@member.has_photo}
        member={@member}
      />
      <p :if={@ask} id="photo-asked" class="hint mt-4">
        {@ask.asked_by} asked on {Service.Format.date_short(
          @ask.ask.asked_at,
          @current_team.timezone
        )}. No photo yet.
        <span :if={@ask.ask.email_status == :failed} id="photo-ask-failed">
          The email did not send. Ask again.
        </span>
      </p>
    </.member_page>
    """
  end

  # A member with no photo, on a team with Photos on (#1028): the line, and the buttons
  # that open Add a photo and Ask for a photo (#1030) for them.
  defp add_photo(assigns) do
    ~H"""
    <div id="no-photo">
      <p>{@member.name} has no photo. An ID card needs one.</p>
      <div class="flex flex-wrap gap-2">
        <.button
          id="add-photo"
          variant={:primary}
          navigate={Web.PhotoCollectionLive.add_path(@member.team, @member)}
        >
          Add a photo
        </.button>
        <.button id="ask-photo" navigate={Web.PhotoAskLive.path(@member.team, @member)}>
          Ask for a photo
        </.button>
      </div>
    </div>
    """
  end

  defp card_content(%{card: nil, active?: false} = assigns) do
    ~H"""
    <p id="no-card">
      {@member.name} is {not_active_text(@standing)}, so they cannot get an ID card.
      <span :if={@revoked_at} id="card-cancelled">
        Their last one was cancelled on {Service.Format.date_short(@revoked_at, @member.team.timezone)}.
      </span>
    </p>
    """
  end

  # No card and no photo, with Photos on: Add a photo comes before Issue ID card, which
  # would only refuse.
  defp card_content(%{card: nil, photos?: true, member: %{has_photo: false}} = assigns) do
    ~H"""
    <.add_photo member={@member} />
    """
  end

  defp card_content(%{card: nil} = assigns) do
    ~H"""
    <div id="no-card">
      <p>
        {@member.name} has no ID card.
        <span :if={@revoked_at} id="card-cancelled">
          Their last one was cancelled on {Service.Format.date_short(
            @revoked_at,
            @member.team.timezone
          )}.
        </span>
      </p>
      <.button id="issue" variant={:primary} phx-click="issue" phx-disable-with="Issuing…">
        Issue ID card
      </.button>
    </div>
    """
  end

  defp card_content(assigns) do
    ~H"""
    <div id="card">
      <div class={@active? && "id-card-columns"}>
        <img
          :if={@active?}
          id="card-image"
          src={@image_path}
          alt={"#{@member.name}'s ID card"}
          class="id-card-image"
        />
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
            <span id="card-phones">{Web.WalletText.summary(@phones, @card)}</span>
          </dd>
        </dl>
      </div>
      <.form_actions>
        <.button
          :if={@active? && @member.email && wallet?()}
          id="email-pass"
          variant={:primary}
          phx-click="email"
          phx-disable-with="Sending…"
          data-confirm={"Email the ID card to #{@member.email}?"}
        >
          Email ID card
        </.button>
        <.button
          :if={@active? && wallet?()}
          id="refresh-card"
          phx-click="refresh"
          phx-disable-with="Refreshing…"
        >
          Refresh ID card
        </.button>
        <%!-- A card out with the placeholder (#1012): saving a photo refreshes it. --%>
        <.button
          :if={@photos? and !@member.has_photo}
          id="add-photo"
          navigate={Web.PhotoCollectionLive.add_path(@member.team, @member)}
        >
          Add a photo
        </.button>
        <.button
          :if={@photos? and !@member.has_photo}
          id="ask-photo"
          navigate={Web.PhotoAskLive.path(@member.team, @member)}
        >
          Ask for a photo
        </.button>
        <.button
          id="cancel-card"
          variant={:danger}
          phx-click="cancel"
          phx-disable-with="Cancelling…"
          data-confirm={cancel_confirm(@member)}
          data-confirm-warning={cancel_warning(@member, @every_member_card?)}
        >
          Cancel ID card
        </.button>
      </.form_actions>
      <p :if={@active? and wallet?()} id="card-delivery" class="hint">
        {delivery_hint(assigns)}
      </p>
      <p :if={!@active? or !@member.has_photo} id="cancel-card-hint" class="hint">
        {cancel_hint(@member, @active?)}
      </p>
    </div>
    """
  end

  defp cancel_confirm(member),
    do:
      "Cancel #{member.name}'s ID card? Their pass shows Cancelled at once, and " <>
        "#{Web.VerifyHost.host()} says the card was cancelled, with nothing about them."

  # Whether they get a new card, and how (#1012). Every member gets a card is named by
  # what it does, since the confirm is far from the switch.
  defp cancel_warning(member, every_member_card?) do
    case {IssueMemberCard.refusal(member, DateTime.utc_now()), every_member_card?} do
      {nil, true} ->
        "Your team gives every current member an ID card, so they get a new one at the next refresh."

      {nil, false} ->
        "To give them a new one, select Issue ID card."

      {:no_photo, true} ->
        "Your team gives every current member with a photo an ID card, so they get a new one " <>
          "after a photo is added."

      {:no_photo, false} ->
        "To give them a new one, add a photo, then select Issue ID card."

      {:not_active, true} ->
        "Your team gives every current member an ID card, so they get a new one if they come back."

      {:not_active, false} ->
        "If they come back, select Issue ID card to give them a new one."
    end
  end

  # A card that says Not active, or has no photo to verify against.
  defp cancel_hint(member, false = _active?),
    do:
      "#{member.name} can still show the pass until it expires, and it says Not active. " <>
        "Cancel it if they should not have it at all."

  defp cancel_hint(member, true = _active?),
    do:
      "#{member.name} has no photo, so whoever verifies the card cannot match it to them. " <>
        "Add one, then select Refresh ID card."

  # Why a member's card is not active, or why they cannot get one.
  defp not_active_text(:retiring), do: "retiring"
  defp not_active_text(_standing), do: "retired"

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

  # The card as the member sees it (#1012), drawn from the team's records. Signed once
  # per load, since each signing makes a new link the browser fetches again. The version
  # moves on Refresh ID card, past the picture's 5-minute browser cache.
  defp card_image_path(card) do
    version = if card.pass_updated_at, do: DateTime.to_unix(card.pass_updated_at), else: 0
    Web.CardLinks.path(card) <> "/image?v=#{version}"
  end

  # The card's page on the verify site, the same one its QR code opens.
  defp verify_url(card), do: MemberCard.verify_url(card.code, Web.VerifyHost.url())
end

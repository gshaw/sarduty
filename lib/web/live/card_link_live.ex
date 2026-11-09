defmodule Web.CardLinkLive do
  use Web, {:live_view_narrow_layout, size: :tool}

  import Web.Components.OpenOnDevice
  import Web.Components.WalletBadges

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.CheckGoogleWalletSave
  alias App.Operation.PushPassUpdates
  alias Web.CardLinks
  alias Web.Navigation
  alias Web.WalletText

  # The page an ID card's email opens (#952): no login, only the link's token, for one
  # card. Apple's and Google's own badges on every device, with no guessing which phone
  # it is. Each opens Web.CardLinkController, which builds the pass on the tap, so a mail
  # scanner or a link preview that opens the page builds nothing. On a computer, Open on
  # your phone has the page's QR code. A card that is replaced, cancelled, or not active
  # says so and offers nothing. Logged in to the card's team, the bar names it, and the
  # card's own member gets a trail back to Your membership, as the reply links lead back
  # into the app: the page stays one page for everyone, with no redirect.
  #
  # Under the Wallet, the card itself (#973), for a member with no Wallet or one who
  # wants a copy on paper: a line on what a copy can't do, Print ID card, then its front
  # and back as SAR Duty draws them, each with Save image. Verify your ID card and Lost
  # your phone go in the sidebar, under Open on your phone; on a phone, under the card.
  #
  # Under it, one quiet line says what SAR Duty sees, and nothing else: no spinner, since
  # a tap can't tell an added card from a cancelled sheet or a card already there. It
  # changes while the page is open: a phone registering the Apple pass, or Google saying
  # it was saved, broadcasts on the card's topic. A tap only starts a check, for 2
  # minutes, on a Wallet that doesn't hold the card yet. Google's save callback only
  # reaches production, so the page asks Google every few seconds
  # (CheckGoogleWalletSave). A replacement lands on the cancelled card's pass with no new
  # registration, so the page nudges those phones to fetch it
  # (PushPassUpdates.nudge_replacement/2). Apple has nothing else to ask: the phone
  # registering is the news.
  @give_up_ms :timer.minutes(2)
  @check_google_ms :timer.seconds(4)
  @nudge_apple_ms :timer.seconds(10)

  def mount(%{"token" => token}, _session, socket) do
    card = CardLinks.find_card(token) || raise Web.Status.NotFound
    team = card.member.team

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(App.PubSub, MemberCard.pass_topic(card.member_id))

    {:ok,
     socket
     |> assign(
       page_title: "Your ID card",
       token: token,
       team: team,
       url: Web.Endpoint.url() <> ~p"/cards/#{token}",
       checking: nil,
       checking_ref: nil,
       own_card?: Enum.any?(socket.assigns.member_logins, &(&1.id == card.member_id))
     )
     |> assign_card(card)
     |> assign_bar_team(team)}
  end

  defp assign_card(socket, card) do
    assign(socket,
      card: card,
      status: MemberCard.link_status(card, DateTime.utc_now()),
      phones: PassRegistration.count_holding(card)
    )
  end

  defp reload_card(socket),
    do: assign_card(socket, MemberCard.get_with_member(socket.assigns.card.id))

  # The tap's link still downloads the pass or opens Google's page; this only starts the
  # check that brings the news sooner.
  def handle_event("adding", %{"wallet" => wallet}, socket) when wallet in ~w(apple google) do
    wallet = if wallet == "apple", do: :apple, else: :google
    {:noreply, start_check(socket, wallet)}
  end

  def handle_info(message, socket)
      when message in [:wallet_changed, :pass_fetched, :card_changed],
      do: {:noreply, socket |> reload_card() |> end_check_when_seen()}

  def handle_info({:give_up, ref}, %{assigns: %{checking_ref: ref}} = socket),
    do: {:noreply, end_check(socket)}

  def handle_info(:check_google, %{assigns: %{checking: :google, card: card}} = socket) do
    {:noreply,
     start_async(socket, :check_google, fn ->
       CheckGoogleWalletSave.call(card, DateTime.utc_now())
     end)}
  end

  def handle_info(:nudge_apple, %{assigns: %{checking: :apple, card: card}} = socket) do
    {:noreply,
     start_async(socket, :nudge_apple, fn ->
       PushPassUpdates.nudge_replacement(card, DateTime.utc_now())
     end)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # A Wallet already holding the card has no news to wait for: Apple doesn't register the
  # pass again, and Google's check would only say it's saved. A second tap on the Wallet
  # being checked keeps the one check.
  defp start_check(%{assigns: %{checking: wallet}} = socket, wallet), do: socket

  defp start_check(socket, wallet) do
    if holds?(socket.assigns, wallet) do
      socket
    else
      ref = make_ref()
      Process.send_after(self(), {:give_up, ref}, @give_up_ms)

      case wallet do
        :google -> Process.send_after(self(), :check_google, @check_google_ms)
        :apple -> Process.send_after(self(), :nudge_apple, @nudge_apple_ms)
      end

      assign(socket, checking: wallet, checking_ref: ref)
    end
  end

  defp holds?(%{phones: phones}, :apple), do: phones > 0
  defp holds?(%{card: card}, :google), do: card.in_wallet_at != nil

  defp end_check_when_seen(%{assigns: %{checking: nil}} = socket), do: socket

  defp end_check_when_seen(%{assigns: %{checking: wallet}} = socket),
    do: if(holds?(socket.assigns, wallet), do: end_check(socket), else: socket)

  defp end_check(socket), do: assign(socket, checking: nil, checking_ref: nil)

  # A save that marks the card broadcasts :wallet_changed; this also covers one that
  # didn't need to. Anything else asks again while the page still checks.
  def handle_async(:check_google, {:ok, :saved}, socket),
    do: {:noreply, socket |> reload_card() |> end_check_when_seen()}

  def handle_async(:check_google, _result, socket) do
    if socket.assigns.checking == :google,
      do: Process.send_after(self(), :check_google, @check_google_ms)

    {:noreply, socket}
  end

  def handle_async(:nudge_apple, _result, socket) do
    if socket.assigns.checking == :apple,
      do: Process.send_after(self(), :nudge_apple, @nudge_apple_ms)

    {:noreply, socket}
  end

  defp assign_bar_team(socket, team) do
    if Navigation.opens_team?(socket.assigns, team),
      do: assign(socket, current_team: team),
      else: socket
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs :if={@own_card?}>
      <:item label="Your membership" path={~p"/teams/#{@team}/me"} />
      <:item label="ID card" />
    </.breadcrumbs>
    <div class="md:flex md:gap-8">
      <div class="md:w-2/3 min-w-0">
        <div class="media mb-4">
          <img src={~p"/teams/#{@team}/logo?shape=square"} alt="" class="logo-md" />
          <p id="card-link-team" class="subheading mb-0">{@team.name}</p>
        </div>
        <h1 class="heading">Your ID card</h1>
        <.card_state
          status={@status}
          team={@team}
          token={@token}
          card={@card}
          phones={@phones}
        />
      </div>
      <div :if={@status == :active} class="md:w-1/3">
        <.open_on_device id="open-on-phone" class={nil} heading="Open on your phone" url={@url}>
          <p class="mb-0">
            Scan the code with your phone's camera. Add your ID card to Wallet there.
          </p>
        </.open_on_device>
        <.card_help card={@card} />
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :team, :map, required: true
  attr :token, :string, required: true
  attr :card, :map, default: nil
  attr :phones, :integer, default: 0

  defp card_state(%{status: :active} = assigns) do
    ~H"""
    <p id="card-link-intro" class="lead">
      Your ID card shows you are a current member of {@team.name}, with your endorsements.
      Show it at the door, or to another agency at an incident.
    </p>
    <.wallet_badges
      id="card-link-wallets"
      apple_href={~p"/cards/#{@token}/apple-wallet"}
      google_href={~p"/cards/#{@token}/google-wallet"}
      apple_click={JS.push("adding", value: %{wallet: "apple"})}
      google_click={JS.push("adding", value: %{wallet: "google"})}
    />
    <p id="card-link-status" class="hint mt-6 mb-0">{WalletText.seen(@phones, @card)}</p>
    <p id="card-link-no-wallet" class="mt-8 mb-0">
      No Wallet? Save each side as an image, or print both. Neither updates. Anyone
      verifying your card scans its code.
    </p>
    <div id="card-link-print" class="mt-2">
      <p class="action mb-0">
        <.a
          id="card-link-print-link"
          href={~p"/cards/#{@token}/pdf"}
          target="_blank"
          icon="printer"
        >Print ID card</.a>
      </p>
      <p class="hint mt-1 mb-0">Both sides at card size, in black on white, to cut out.</p>
    </div>
    <.card_side id="card-link-front" class="mt-6" token={@token} side="front" card={@card} />
    <.card_side id="card-link-back" class="mt-6" token={@token} side="back" card={@card} />
    """
  end

  defp card_state(%{status: :replaced} = assigns) do
    ~H"""
    <p id="card-link-replaced">This ID card was replaced. Use the link in your newest email.</p>
    """
  end

  defp card_state(%{status: :cancelled} = assigns) do
    ~H"""
    <p id="card-link-cancelled">This ID card was cancelled. Ask a team admin if you need one.</p>
    """
  end

  defp card_state(%{status: :inactive} = assigns) do
    ~H"""
    <p id="card-link-inactive">This ID card is not active. Ask a team admin if you need one.</p>
    """
  end

  attr :card, :map, required: true

  # Under Open on your phone on a computer, and under the card on a phone, where the QR
  # code hides.
  defp card_help(assigns) do
    ~H"""
    <aside id="card-link-help" class="mt-8">
      <%!-- The verify site is SAR Duty's own: the same tab, with the arrow. --%>
      <div id="card-link-verify">
        <p class="action mb-0">
          <.a id="card-link-verify-link" href={verify_url(@card)}>Verify your ID card</.a>
        </p>
        <p class="hint mt-1 mb-0">What someone verifying your card sees.</p>
      </div>
      <p id="card-link-lost" class="hint mt-4 mb-0">
        Lost your phone? Ask a team admin to replace your ID card. This link is yours alone.
      </p>
    </aside>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :token, :string, required: true
  attr :side, :string, required: true, doc: "front or back"
  attr :card, :map, required: true

  # One side as SAR Duty draws it (DrawMemberCard, #973), with Save image under it. A
  # long press on the picture saves it on a phone too.
  defp card_side(assigns) do
    ~H"""
    <div id={@id} class={@class}>
      <p class="hint mb-2">{String.capitalize(@side)}</p>
      <img
        src={~p"/cards/#{@token}/#{@side}"}
        alt={"#{@card.member.name}'s ID card, #{@side}"}
        class="id-card-side"
      />
      <p class="action mt-2 mb-0">
        <.a
          id={"#{@id}-save"}
          href={~p"/cards/#{@token}/#{@side}"}
          download={"#{@card.member.team.subdomain}-id-card-#{@side}.png"}
          phx-hook="SaveImage"
          icon="download"
        >Save {@side} image</.a>
      </p>
    </div>
    """
  end

  # The card's page on the verify site, as a checker sees it.
  defp verify_url(card), do: MemberCard.verify_url(card.code, Web.VerifyHost.url())
end

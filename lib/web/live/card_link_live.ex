defmodule Web.CardLinkLive do
  use Web, {:live_view_narrow_layout, size: :tool}

  import Web.Components.OpenOnDevice
  import Web.Components.WalletBadges

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias Web.CardLinks
  alias Web.Navigation
  alias Web.WalletText

  # The page an ID card's email opens (#952): no login, only the link's token, for one
  # card. Apple's and Google's own badges on every device, with no guessing which phone
  # it is. Each opens Web.CardLinkController, which builds the pass on the tap, so a mail
  # scanner or a link preview that opens the page builds nothing. On a computer, Open on
  # your phone has the page's QR code. A card that is replaced, cancelled, or not active
  # says so and offers nothing. Logged in to the card's team, the bar names it.
  #
  # In Wallet says what SAR Duty knows, and changes while the page is open: a phone
  # registering the Apple pass, or Google saying it was saved, broadcasts on the card's
  # topic. A tap on a badge swaps the badges for what the page waits on, until that
  # news comes, the member cancels, or 2 minutes pass.
  @give_up_ms :timer.minutes(2)

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
       waiting: nil,
       waiting_ref: nil,
       not_yet?: false
     )
     |> assign_card(card)
     |> assign_bar_team(team)}
  end

  defp assign_card(socket, card) do
    assign(socket,
      card: card,
      status: MemberCard.link_status(card, DateTime.utc_now()),
      phones: length(PassRegistration.get_all_for_serial(card))
    )
  end

  defp reload_card(socket),
    do: assign_card(socket, MemberCard.get_with_member(socket.assigns.card.id))

  # The tap's link still downloads the pass or opens Google's page; this only shows what
  # the page waits on.
  def handle_event("adding", %{"wallet" => wallet}, socket) when wallet in ~w(apple google) do
    ref = make_ref()
    Process.send_after(self(), {:give_up, ref}, @give_up_ms)
    waiting = if wallet == "apple", do: :apple, else: :google
    {:noreply, assign(socket, waiting: waiting, waiting_ref: ref, not_yet?: false)}
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, waiting: nil, waiting_ref: nil)}

  def handle_info(:wallet_changed, socket),
    do: {:noreply, socket |> reload_card() |> assign(waiting: nil, waiting_ref: nil)}

  def handle_info(message, socket) when message in [:pass_fetched, :card_changed],
    do: {:noreply, reload_card(socket)}

  def handle_info({:give_up, ref}, %{assigns: %{waiting_ref: ref}} = socket),
    do: {:noreply, assign(socket, waiting: nil, waiting_ref: nil, not_yet?: true)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_bar_team(socket, team) do
    if Navigation.opens_team?(socket.assigns, team),
      do: assign(socket, current_team: team),
      else: socket
  end

  def render(assigns) do
    ~H"""
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
          waiting={@waiting}
          not_yet?={@not_yet?}
        />
      </div>
      <.open_on_device
        :if={@status == :active}
        id="open-on-phone"
        heading="Open on your phone"
        url={@url}
      >
        <p class="mb-0">
          Scan the code with your phone's camera, then add your ID card to Wallet there.
        </p>
      </.open_on_device>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :team, :map, required: true
  attr :token, :string, required: true
  attr :card, :map, default: nil
  attr :phones, :integer, default: 0
  attr :waiting, :atom, default: nil
  attr :not_yet?, :boolean, default: false

  defp card_state(%{status: :active} = assigns) do
    ~H"""
    <p id="card-link-intro" class="lead">
      Your ID card shows you are a current member of {@team.name}, with your endorsements.
      Show it at the door, or to another agency on a search.
    </p>
    <div :if={@waiting} id="card-link-waiting" class="flex flex-wrap items-center gap-3">
      <.spinner :if={@waiting == :apple}>
        Waiting for your phone to add it to Apple Wallet…
      </.spinner>
      <.spinner :if={@waiting == :google}>Opening Google Wallet…</.spinner>
      <.a id="card-link-cancel" href="#" phx-click="cancel">Cancel</.a>
    </div>
    <.wallet_badges
      :if={!@waiting}
      id="card-link-wallets"
      apple_href={~p"/cards/#{@token}/apple-wallet"}
      google_href={~p"/cards/#{@token}/google-wallet"}
      apple_click={JS.push("adding", value: %{wallet: "apple"})}
      google_click={JS.push("adding", value: %{wallet: "google"})}
    />
    <p :if={@not_yet? and !@waiting} id="card-link-not-yet" class="hint mt-2 mb-0">
      Your phone hasn't added it yet. Try again.
    </p>
    <section id="card-link-status" class="mt-8">
      <h2 class="heading">In Wallet</h2>
      <p :if={BuildApplePass.configured?()} id="card-link-apple-status" class="mb-1">
        {WalletText.apple(@phones, @card, @team.timezone) || "Not in Apple Wallet yet"}
      </p>
      <p :if={BuildGooglePass.configured?()} id="card-link-google-status" class="mb-1">
        {WalletText.google(@card) || "Not in Google Wallet yet"}
      </p>
      <p class="hint mb-0">This changes as soon as your phone or Google tells SAR Duty.</p>
    </section>
    <p id="card-link-lost" class="hint mt-6 mb-0">
      Lost your phone? Ask a team admin to replace your ID card. This link is yours alone.
    </p>
    """
  end

  defp card_state(%{status: :replaced} = assigns) do
    ~H"""
    <p id="card-link-replaced">This ID card was replaced. Use the link in your newest email.</p>
    """
  end

  defp card_state(%{status: :cancelled} = assigns) do
    ~H"""
    <p id="card-link-cancelled">This ID card was cancelled.</p>
    """
  end

  defp card_state(%{status: :inactive} = assigns) do
    ~H"""
    <p id="card-link-inactive">This ID card is not active.</p>
    """
  end
end

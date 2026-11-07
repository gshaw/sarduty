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
  # says so and offers nothing. Logged in to the card's team, the bar names it.
  #
  # Under it, one quiet line says what SAR Duty sees, and changes while the page is open:
  # a phone registering the Apple pass, or Google saying it was saved, broadcasts on the
  # card's topic. A tap dims its badge and turns the line into what the page waits on,
  # since the adding happens off the page, until that news comes or 2 minutes pass.
  # Google's save callback only reaches production, so while the page waits on Google it
  # also asks Google every few seconds (CheckGoogleWalletSave). Apple has nothing to ask:
  # the phone registering is the news. A replacement lands on the cancelled card's pass
  # with no new registration, so while the page waits on Apple it nudges those phones
  # to fetch it (PushPassUpdates.nudge_replacement/2).
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
       waiting: nil,
       waiting_ref: nil
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

  # The tap's link still downloads the pass or opens Google's page; this only shows what
  # the page waits on.
  def handle_event("adding", %{"wallet" => wallet}, socket) when wallet in ~w(apple google) do
    ref = make_ref()
    Process.send_after(self(), {:give_up, ref}, @give_up_ms)
    waiting = if wallet == "apple", do: :apple, else: :google
    if waiting == :google, do: Process.send_after(self(), :check_google, @check_google_ms)
    if waiting == :apple, do: Process.send_after(self(), :nudge_apple, @nudge_apple_ms)
    {:noreply, assign(socket, waiting: waiting, waiting_ref: ref)}
  end

  def handle_info(message, socket)
      when message in [:wallet_changed, :pass_fetched, :card_changed],
      do: {:noreply, socket |> reload_card() |> end_wait_when_seen()}

  def handle_info({:give_up, ref}, %{assigns: %{waiting_ref: ref}} = socket),
    do: {:noreply, assign(socket, waiting: nil, waiting_ref: nil)}

  def handle_info(:check_google, %{assigns: %{waiting: :google, card: card}} = socket) do
    {:noreply,
     start_async(socket, :check_google, fn ->
       CheckGoogleWalletSave.call(card, DateTime.utc_now())
     end)}
  end

  def handle_info(:nudge_apple, %{assigns: %{waiting: :apple, card: card}} = socket) do
    {:noreply,
     start_async(socket, :nudge_apple, fn ->
       PushPassUpdates.nudge_replacement(card, DateTime.utc_now())
     end)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # The wait ends once SAR Duty sees the card in the Wallet it waited on.
  defp end_wait_when_seen(%{assigns: %{waiting: :apple, phones: phones}} = socket)
       when phones > 0,
       do: assign(socket, waiting: nil, waiting_ref: nil)

  defp end_wait_when_seen(
         %{assigns: %{waiting: :google, card: %{in_wallet_at: %DateTime{}}}} = socket
       ),
       do: assign(socket, waiting: nil, waiting_ref: nil)

  defp end_wait_when_seen(socket), do: socket

  # A save broadcasts :wallet_changed, which ends the wait. Anything else asks again
  # while the page still waits.
  def handle_async(:check_google, {:ok, :saved}, socket), do: {:noreply, socket}

  def handle_async(:nudge_apple, _result, socket) do
    if socket.assigns.waiting == :apple,
      do: Process.send_after(self(), :nudge_apple, @nudge_apple_ms)

    {:noreply, socket}
  end

  def handle_async(:check_google, _result, socket) do
    if socket.assigns.waiting == :google,
      do: Process.send_after(self(), :check_google, @check_google_ms)

    {:noreply, socket}
  end

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

  defp card_state(%{status: :active} = assigns) do
    ~H"""
    <p id="card-link-intro" class="lead">
      Your ID card shows you are a current member of {@team.name}, with your endorsements.
      Show it at the door, or to another agency on a search.
    </p>
    <.wallet_badges
      id="card-link-wallets"
      apple_href={~p"/cards/#{@token}/apple-wallet"}
      google_href={~p"/cards/#{@token}/google-wallet"}
      apple_click={JS.push("adding", value: %{wallet: "apple"})}
      google_click={JS.push("adding", value: %{wallet: "google"})}
      adding={@waiting}
    />
    <p id="card-link-status" class="hint mt-6 mb-0">
      <.spinner :if={@waiting == :apple}>Waiting for your phone to add it to Apple Wallet…</.spinner>
      <.spinner :if={@waiting == :google}>Waiting for Google Wallet in the new tab…</.spinner>
      <span :if={!@waiting}>{WalletText.seen(@phones, @card)}</span>
    </p>
    <p id="card-link-lost" class="hint mt-2 mb-0">
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

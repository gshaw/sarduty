defmodule Web.CardLinkLive do
  use Web, {:live_view_narrow_layout, size: :tool}

  import Web.Components.OpenOnDevice

  alias App.Model.MemberCard
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias Web.CardLinks
  alias Web.Navigation

  # The page an ID card's email opens (#952): no login, only the link's token, for one
  # card. Apple's and Google's own badges on every device, with no guessing which phone
  # it is. Each opens Web.CardLinkController, which builds the pass on the tap, so a mail
  # scanner or a link preview that opens the page builds nothing. On a computer, Open on
  # your phone has the page's QR code. A card that is replaced, cancelled, or not active
  # says so and offers nothing. Logged in to the card's team, the bar names it.
  def mount(%{"token" => token}, _session, socket) do
    card = CardLinks.find_card(token) || raise Web.Status.NotFound
    team = card.member.team

    {:ok,
     socket
     |> assign(
       page_title: "Your ID card",
       token: token,
       card: card,
       member: card.member,
       team: team,
       status: MemberCard.link_status(card, DateTime.utc_now()),
       url: Web.Endpoint.url() <> ~p"/cards/#{token}"
     )
     |> assign_bar_team(team)}
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
        <.card_state status={@status} member={@member} team={@team} token={@token} />
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
  attr :member, :map, required: true
  attr :team, :map, required: true
  attr :token, :string, required: true

  defp card_state(%{status: :active} = assigns) do
    ~H"""
    <p id="card-link-intro" class="lead">
      {@member.name}, your ID card shows you are a current member of {@team.name}.
      Show it at the door, or to another team on a search.
    </p>
    <div id="card-link-wallets" class="wallet-badges">
      <a
        :if={BuildApplePass.configured?()}
        id="card-link-apple"
        href={~p"/cards/#{@token}/apple-wallet"}
      >
        <img src={~p"/images/add-to-apple-wallet.svg"} alt="Add to Apple Wallet" />
      </a>
      <a
        :if={BuildGooglePass.configured?()}
        id="card-link-google"
        href={~p"/cards/#{@token}/google-wallet"}
      >
        <img src={~p"/images/add-to-google-wallet.png"} alt="Add to Google Wallet" />
      </a>
    </div>
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

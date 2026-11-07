defmodule Web.Components.WalletBadges do
  @moduledoc """
  Apple's and Google's own Add to Wallet badges, side by side at 48px, Google's minimum
  (#952). Only the card's page has them: Your membership and the Dashboard's to-do have
  a link, Add ID card to Wallet, that opens it, so a member learns one page, and on a
  computer gets its QR code. Each badge shows only when its Wallet is set up. They're
  links to a route that builds the pass on the tap, never `<.button>`s: both brands
  forbid changing the artwork. Google's is its condensed button, two lines like Apple's,
  so the pair fits on one line on a 375px phone. See /styles/wallet-badges.
  """
  use Web, :function_component

  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass

  @doc "Whether either Wallet is set up, so a link to the card's page has something to offer."
  def any?, do: BuildApplePass.configured?() or BuildGooglePass.configured?()

  attr :id, :string,
    required: true,
    doc: "the row's id; the badges are <id>-apple and <id>-google"

  attr :apple_href, :string, required: true, doc: "the route that sends the .pkpass"

  attr :google_href, :string,
    required: true,
    doc: "the route that redirects to Google's save link"

  attr :apple_click, :any, default: nil, doc: "a phx-click for a tap on Apple's badge"
  attr :google_click, :any, default: nil, doc: "a phx-click for a tap on Google's badge"
  attr :class, :any, default: nil

  # A phx-click on a link with a real href doesn't stop the link, so the pass still
  # downloads or Google's page still opens while the page hears of the tap.
  def wallet_badges(assigns) do
    ~H"""
    <div
      :if={any?()}
      id={@id}
      class={["wallet-badges", @class]}
    >
      <a
        :if={BuildApplePass.configured?()}
        id={"#{@id}-apple"}
        href={@apple_href}
        phx-click={@apple_click}
      >
        <img src={~p"/images/add-to-apple-wallet.svg"} alt="Add to Apple Wallet" />
      </a>
      <a
        :if={BuildGooglePass.configured?()}
        id={"#{@id}-google"}
        href={@google_href}
        phx-click={@google_click}
      >
        <img src={~p"/images/add-to-google-wallet.svg"} alt="Add to Google Wallet" />
      </a>
    </div>
    """
  end
end

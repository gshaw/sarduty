defmodule Web.Components.WalletBadges do
  @moduledoc """
  Apple's and Google's own Add to Wallet badges, side by side at 48px, Google's minimum
  (#952). The one way a member adds their ID card: the card's page, Your membership, and
  the Dashboard's to-do. Each shows only when its Wallet is set up. They're links to a
  route that builds the pass on the tap, never `<.button>`s: both brands forbid changing
  the artwork. Google's is its condensed button, two lines like Apple's, so the pair fits
  on one line on a 375px phone. See /styles/wallet-badges.
  """
  use Web, :function_component

  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass

  attr :id, :string,
    required: true,
    doc: "the row's id; the badges are <id>-apple and <id>-google"

  attr :apple_href, :string, required: true, doc: "the route that sends the .pkpass"

  attr :google_href, :string,
    required: true,
    doc: "the route that redirects to Google's save link"

  attr :class, :any, default: nil

  def wallet_badges(assigns) do
    ~H"""
    <div
      :if={BuildApplePass.configured?() or BuildGooglePass.configured?()}
      id={@id}
      class={["wallet-badges", @class]}
    >
      <a :if={BuildApplePass.configured?()} id={"#{@id}-apple"} href={@apple_href}>
        <img src={~p"/images/add-to-apple-wallet.svg"} alt="Add to Apple Wallet" />
      </a>
      <a :if={BuildGooglePass.configured?()} id={"#{@id}-google"} href={@google_href}>
        <img src={~p"/images/add-to-google-wallet.svg"} alt="Add to Google Wallet" />
      </a>
    </div>
    """
  end
end

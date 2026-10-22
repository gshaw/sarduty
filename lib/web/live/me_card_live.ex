defmodule Web.MeCardLive do
  use Web, {:live_view_app_layout, access: :member}

  alias App.Model.MemberCard
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass

  # A member's ID card (#156), /teams/:subdomain/me/card: the Wallet buttons and the
  # verify link. Members don't issue cards; team admins do (docs/member-cards.md).
  def mount(_params, _session, socket) do
    member = socket.assigns.current_member
    socket = assign(socket, :member, member)

    socket =
      socket
      |> assign(:page_title, "ID card")
      |> assign(:card, MemberCard.find_current(member.team, member))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">ID card</h1>
      <.card_content card={@card} member={@member} />
    </div>
    """
  end

  defp card_content(%{card: nil, member: %{team: %{id_cards_enabled: false}}} = assigns) do
    ~H"""
    <p id="no-card">Your team does not issue ID cards in SAR Duty.</p>
    """
  end

  defp card_content(%{card: nil} = assigns) do
    ~H"""
    <p id="no-card">You do not have an ID card yet. Ask a team admin to issue one.</p>
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

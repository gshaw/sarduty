defmodule Web.MeLive do
  use Web, :live_view_narrow_layout

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.IssueMemberCard

  # A member's own page (#156), /teams/:subdomain/me: their ID card and their tax credit
  # letters. `member` comes from the login (Web.UserAuth, :ensure_team_member), never from
  # the URL. Mostly read on a phone.
  def mount(_params, _session, socket) do
    member = socket.assigns.member

    socket =
      socket
      |> assign(:page_title, member.team.name)
      |> assign(:card, MemberCard.find_current(member.team, member))
      |> assign(:letters, TaxCreditLetter.get_all_for_member(member))

    {:ok, socket}
  end

  # The member gets a card only when they have none, so a second tap can't cancel the
  # one just added to Wallet. The login is checked again, in case the team turned member
  # logins off since the page opened.
  def handle_event("issue", _params, socket) do
    %{current_user: user, member: member} = socket.assigns

    case user.email
         |> Member.get_logins(DateTime.utc_now())
         |> Enum.find(&(&1.id == member.id)) do
      nil ->
        {:noreply, redirect(socket, to: ~p"/")}

      member ->
        card =
          case MemberCard.find_current(member.team, member) do
            nil ->
              {:ok, card} = IssueMemberCard.call(member.team, member, DateTime.utc_now())
              card

            card ->
              card
          end

        {:noreply, socket |> assign(:card, card) |> put_flash(:info, "Your ID card is ready.")}
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">{@member.team.name}</h1>
      <p class="lead">{@member.name}</p>

      <h2 class="subheading mt-8">ID card</h2>
      <.card_content card={@card} member={@member} />

      <h2 class="subheading mt-8">Tax credit letters</h2>
      <.empty_state :if={@letters == []} id="no-letters" title="No tax credit letters yet">
        Your team admins make them after each year ends.
      </.empty_state>
      <ul :if={@letters != []} id="letters" class="flex flex-col gap-4">
        <li :for={letter <- @letters} id={"letter-#{letter.id}"}>
          <.button href={~p"/teams/#{@member.team}/me/tax-credit-letters/#{letter.id}/pdf"}>
            Download {letter.year} letter
          </.button>
          <span class="hint block mt-1">
            Made {Service.Format.date_long(letter.inserted_at, @member.team.timezone)}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp card_content(%{card: nil} = assigns) do
    ~H"""
    <div id="no-card">
      <p>You do not have an ID card yet. Get one, then add it to your phone's Wallet.</p>
      <.form_actions>
        <.button id="issue" variant={:primary} phx-click="issue" phx-disable-with="Making card…">
          Get ID card
        </.button>
      </.form_actions>
    </div>
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

defmodule Web.MemberCardLive do
  use Web, :live_view_app_layout

  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildCardQualifications
  alias App.Operation.BuildGooglePass
  alias App.Operation.EmailMemberCard
  alias App.Operation.IssueMemberCard
  alias App.Operation.RevokeMemberCard
  alias App.Operation.SendTestPassUpdate
  alias App.Repo

  # A phone fetching the pass ticks "last fetched" over. The topic is by the URL's member
  # id, but the message carries nothing; the card is looked up through the team.
  def mount(params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(App.PubSub, MemberCard.pass_topic(params["id"]))

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    member = team |> Member.find!(params["id"]) |> Repo.preload([:team])

    socket =
      socket
      |> assign(:page_title, "#{member.name} - ID Card")
      |> assign(:member, member)
      |> assign_card(MemberCard.find_current(team, member))
      |> assign(:qualifications, BuildCardQualifications.call(team, member, DateTime.utc_now()))

    {:noreply, socket}
  end

  def handle_event("issue", _params, socket) do
    %{current_team: team, member: member} = socket.assigns
    {:ok, card} = IssueMemberCard.call(team, member, DateTime.utc_now())
    {:noreply, socket |> assign_card(card) |> put_flash(:info, "Issued a new card.")}
  end

  def handle_event("email", _params, socket) do
    %{current_team: team, member: member} = socket.assigns

    socket =
      case EmailMemberCard.call(team, member, DateTime.utc_now()) do
        :ok -> put_flash(socket, :info, "Emailed the pass to #{member.email}.")
        {:error, :no_email} -> put_flash(socket, :error, "#{member.name} has no email in D4H.")
        {:error, _reason} -> put_flash(socket, :error, "The email didn't send. Try again.")
      end

    {:noreply, socket}
  end

  def handle_event("revoke", _params, socket) do
    %{current_team: team, member: member} = socket.assigns
    :ok = RevokeMemberCard.call(team, member, DateTime.utc_now())
    {:noreply, socket |> assign_card(nil) |> put_flash(:info, "Cancelled the card.")}
  end

  def handle_event("test-update", _params, socket) do
    %{current_team: team, member: member} = socket.assigns

    case MemberCard.find_current(team, member) do
      nil ->
        {:noreply, assign_card(socket, nil)}

      card ->
        {:ok, phones} = SendTestPassUpdate.call(card, DateTime.utc_now())
        count = Service.Format.count(phones, one: "1 phone", many: "%d phones")
        message = "Sent a test update to #{count}. Each should show a notice within a minute."
        {:noreply, socket |> assign_card(Repo.reload!(card)) |> put_flash(:info, message)}
    end
  end

  def handle_info(:pass_fetched, socket) do
    %{current_team: team, member: member} = socket.assigns
    {:noreply, assign_card(socket, MemberCard.find_current(team, member))}
  end

  # Swoosh's test adapter sends each email to the process that sent it.
  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_card(socket, card) do
    phones = if card, do: length(PassRegistration.get_all_for_serial(card)), else: 0
    socket |> assign(:card, card) |> assign(:phones, phones)
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Members" path={~p"/#{@current_team.subdomain}/members/"} />
      <:item label="ID Card" />
    </.breadcrumbs>

    <h1 class="title">{@member.name}</h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content member={@member} />
      </aside>
      <main class="content-2/3">
        <.member_tabs member={@member} active_tab={:card} />
        <.card_content
          card={@card}
          member={@member}
          qualifications={@qualifications}
          phones={@phones}
        />
      </main>
    </div>
    """
  end

  defp card_content(%{card: nil} = assigns) do
    ~H"""
    <div id="no-card">
      <p>{@member.name} has no ID card.</p>
      <p class="mt-p">
        <.button id="issue" variant={:primary} phx-click="issue">Issue a card</.button>
      </p>
    </div>
    """
  end

  defp card_content(assigns) do
    ~H"""
    <div id="card">
      <dl>
        <dt>Code</dt>
        <dd id="card-code" class="font-mono text-lg">{MemberCard.format_code(@card.code)}</dd>
        <dt>Issued</dt>
        <dd>{Service.Format.date_long(@card.inserted_at, @member.team.timezone)}</dd>
        <dt>On the back</dt>
        <dd id="card-qualifications">
          <div :for={q <- @qualifications}>
            {BuildCardQualifications.describe(q, @member.team.timezone)}
          </div>
          <.a :if={@qualifications == []} navigate={~p"/settings/cards"}>
            Pick qualifications to show
          </.a>
        </dd>
        <dt :if={BuildApplePass.configured?()}>Apple Wallet</dt>
        <dd :if={BuildApplePass.configured?()}>
          <span id="card-phones">{phone_status(@phones, @card, @member.team.timezone)}</span>
          <.button
            :if={@phones > 0}
            id="test-update"
            size={:sm}
            phx-click="test-update"
            phx-disable-with="Sending…"
          >
            Send test update
          </.button>
        </dd>
      </dl>
      <p class="mt-p">
        Anyone can check this card at <.a id="card-verify-link" href={verify_url(@card)}>
          {Web.VerifyHost.host()}/{MemberCard.format_code(@card.code)}
        </.a>.
      </p>
      <p :if={BuildApplePass.configured?() or BuildGooglePass.configured?()} class="mt-p flex gap-2">
        <.button
          :if={@member.email}
          id="email-pass"
          variant={:primary}
          phx-click="email"
          phx-disable-with="Sending…"
          data-confirm={"Email the wallet pass to #{@member.email}?"}
        >
          Email pass to member
        </.button>
        <.button
          :if={BuildApplePass.configured?()}
          id="apple-pass"
          href={~p"/#{@member.team.subdomain}/members/#{@member.id}/card/pass"}
        >
          Download Apple Wallet pass
        </.button>
        <.button
          :if={BuildGooglePass.configured?()}
          id="google-pass"
          href={~p"/#{@member.team.subdomain}/members/#{@member.id}/card/google-pass"}
        >
          Add to Google Wallet
        </.button>
      </p>
      <p class="mt-p flex gap-2">
        <.button
          id="replace"
          phx-click="issue"
          data-confirm="Replace this card? The old code stops working."
        >
          Replace card
        </.button>
        <.button
          id="revoke"
          variant={:danger}
          phx-click="revoke"
          data-confirm="Cancel this card? The code stops working."
        >
          Cancel card
        </.button>
      </p>
    </div>
    """
  end

  defp phone_status(0, _card, _timezone), do: "Not on a phone yet"

  defp phone_status(phones, card, timezone) do
    on = "On #{Service.Format.count(phones, one: "1 phone", many: "%d phones")}"

    case card.pass_fetched_at do
      nil -> on
      fetched_at -> "#{on} · last fetched #{Service.Format.month_day_time(fetched_at, timezone)}"
    end
  end

  # The card's page on the verify site, the same one its QR code opens.
  defp verify_url(card), do: "#{Web.VerifyHost.url()}/#{MemberCard.format_code(card.code)}"
end

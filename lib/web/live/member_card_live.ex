defmodule Web.MemberCardLive do
  use Web, :live_view_app_layout

  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Operation.BuildApplePass
  alias App.Operation.EmailMemberCard
  alias App.Operation.IssueMemberCard
  alias App.Operation.RevokeMemberCard
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    team = socket.assigns.current_team
    member = team |> Member.find!(params["id"]) |> Repo.preload([:team])

    socket =
      socket
      |> assign(:page_title, "#{member.name} - ID Card")
      |> assign(:member, member)
      |> assign(:card, MemberCard.find_current(team, member))

    {:noreply, socket}
  end

  def handle_event("issue", _params, socket) do
    %{current_team: team, member: member} = socket.assigns
    {:ok, card} = IssueMemberCard.call(team, member, DateTime.utc_now())
    {:noreply, socket |> assign(:card, card) |> put_flash(:info, "Issued a new card.")}
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
    {:noreply, socket |> assign(:card, nil) |> put_flash(:info, "Cancelled the card.")}
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
        <.card_content card={@card} member={@member} />
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
      </dl>
      <p class="mt-p">
        Anyone can check this card at <.a navigate={
          ~p"/verify?#{[code: MemberCard.format_code(@card.code)]}"
        }>sarduty.com/verify</.a>.
      </p>
      <p :if={BuildApplePass.configured?()} class="mt-p flex gap-2">
        <.button
          :if={@member.email}
          id="email-pass"
          variant={:primary}
          phx-click="email"
          phx-disable-with="Sending…"
          data-confirm={"Email the Apple Wallet pass to #{@member.email}?"}
        >
          Email pass to member
        </.button>
        <.button id="apple-pass" href={~p"/#{@member.team.subdomain}/members/#{@member.id}/card/pass"}>
          Download Apple Wallet pass
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
end

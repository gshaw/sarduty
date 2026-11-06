defmodule Web.Settings.FeaturesLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.Team
  alias App.Operation.IssueEveryMemberCard
  alias App.Operation.SetTeamFeature

  # The team's features, /teams/:subdomain/settings/features: one switch each, saved when
  # flipped, A to Z. Certificates and chores need member logins, so they sit under it, A
  # to Z too. MCP (Agents) and ID
  # cards are SAR Duty's to turn on, from /admin/teams/:id (App.Operation.SetTeamMCP,
  # App.Operation.SetTeamIdCards), so they show only as on or off. A team asks for ID
  # cards; MCP isn't offered, so it shows only once on. Every member gets a card (#893)
  # sits under ID cards, for a team admin.
  def mount(_params, _session, socket) do
    socket
    |> assign(page_title: "Team settings · Features", reading_whiteboard?: false)
    |> assign_cards()
    |> then(&{:ok, &1})
  end

  # What turning on Every member gets a card would do, and who gets no email.
  defp assign_cards(%{assigns: %{current_team: %Team{id_cards_enabled: true} = team}} = socket) do
    now = DateTime.utc_now()

    assign(socket,
      card_plan: IssueEveryMemberCard.preview(team, now),
      without_email: IssueEveryMemberCard.without_email(team, now)
    )
  end

  defp assign_cards(socket), do: assign(socket, card_plan: nil, without_email: [])

  def handle_event("set", %{"feature" => "every_member_card"}, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    now = DateTime.utc_now()

    case IssueEveryMemberCard.set(team, !team.every_member_card, user, now) do
      {:ok, team, queued} ->
        socket
        |> assign(current_team: team)
        |> assign_cards()
        |> put_flash(:info, every_member_card_message(team, queued))
        |> then(&{:noreply, &1})

      {:error, :id_cards_off} ->
        {:noreply,
         put_flash(socket, :error, "ID cards are off. Email support@sarduty.com to ask.")}
    end
  end

  def handle_event("set", %{"feature" => name}, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    feature = Enum.find(SetTeamFeature.features(), &(Atom.to_string(&1) == name))
    {:ok, team} = SetTeamFeature.call(team, feature, !on?(team, feature), user)

    socket
    |> assign(current_team: team)
    |> put_flash(:info, message(team, feature))
    |> read_whiteboard(feature)
    |> then(&{:noreply, &1})
  end

  # The whiteboard's notes come from D4H, read after the switch has answered.
  defp read_whiteboard(
         %{assigns: %{current_team: %{whiteboard_enabled: true}}} = socket,
         :whiteboard
       ) do
    team = socket.assigns.current_team

    socket
    |> assign(reading_whiteboard?: true)
    |> start_async(:whiteboard, fn -> SetTeamFeature.read_whiteboard(team) end)
  end

  defp read_whiteboard(socket, _feature), do: socket

  def handle_async(:whiteboard, result, socket) do
    socket = assign(socket, reading_whiteboard?: false)

    case result do
      {:ok, team} -> {:noreply, assign(socket, current_team: team)}
      {:exit, _reason} -> {:noreply, socket}
    end
  end

  defp on?(team, :member_logins), do: team.member_logins
  defp on?(team, :chores), do: team.chores_enabled
  defp on?(team, :certificates), do: team.certificates_enabled
  defp on?(team, :whiteboard), do: team.whiteboard_enabled
  defp on?(team, :travel), do: team.travel_enabled

  defp message(%{member_logins: true}, :member_logins),
    do: "Member logins turned on. Members can log in now."

  defp message(_team, :member_logins), do: "Member logins turned off. Members cannot log in."
  defp message(%{chores_enabled: true}, :chores), do: "Chores turned on."
  defp message(_team, :chores), do: "Chores turned off."
  defp message(%{certificates_enabled: true}, :certificates), do: "Certificates turned on."
  defp message(_team, :certificates), do: "Certificates turned off."
  defp message(%{whiteboard_enabled: true}, :whiteboard), do: "Whiteboard turned on."
  defp message(_team, :whiteboard), do: "Whiteboard turned off."
  defp message(%{travel_enabled: true}, :travel), do: "Travel turned on."
  defp message(_team, :travel), do: "Travel turned off."

  defp every_member_card_message(%{every_member_card: false}, _queued),
    do: "Every member gets a card turned off. Cards already made stay."

  defp every_member_card_message(_team, 0), do: "Every member gets a card turned on."

  defp every_member_card_message(_team, queued) do
    "Every member gets a card turned on. Making " <>
      Service.Format.count(queued, one: "%d card", many: "%d cards") <> " now."
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:features} />
    <div class="measure">
      <p class="lead">Turn on what your team uses.</p>

      <div id="features" class="flex flex-col gap-6">
        <.set_by_sar_duty
          :if={@current_team.mcp_enabled}
          id="feature-mcp"
          label="Agents"
          on?={true}
        >
          Team admins connect an AI agent, such as Claude or ChatGPT, that helps write
          reports. <.a navigate={~p"/teams/#{@current_team}/settings/mcp"}>Agents</.a>
        </.set_by_sar_duty>

        <.set_by_sar_duty id="feature-id-cards" label="ID cards" on?={@current_team.id_cards_enabled}>
          Members add their ID card to Apple Wallet or Google Wallet. SAR Duty turns ID cards
          on. Email support@sarduty.com to ask.
        </.set_by_sar_duty>

        <div class="flex flex-col gap-6 pl-8">
          <.switch
            id="feature-every-member-card"
            label="Every member gets a card"
            checked={@current_team.every_member_card}
            disabled={!@current_team.id_cards_enabled}
            phx-click="set"
            phx-value-feature="every_member_card"
            {turn_on_cards_confirm(@current_team, @card_plan)}
          >
            Every current member gets an ID card, emailed to them. New members get theirs at
            the next refresh.
            <span :if={!@current_team.id_cards_enabled} class="block">
              Works once ID cards are on.
            </span>
            <span :if={@without_email != []} id="every-member-card-no-email" class="block">
              {no_email_text(@without_email, @service)}
            </span>
          </.switch>
        </div>

        <.switch
          id="feature-member-logins"
          label="Member logins"
          checked={@current_team.member_logins}
          phx-click="set"
          phx-value-feature="member_logins"
          {turn_off_confirm(@current_team.member_logins, "Turn off member logins?", "Members cannot log in, and a member's next page says it is not found.", "Turn off member logins")}
        >
          Members log in with the email or mobile number your team has in {@service}. They see
          the Dashboard, the members list, and Your membership, and reply to activities.
          Retired members cannot log in.
        </.switch>

        <div class="flex flex-col gap-6 pl-8">
          <.switch
            id="feature-certificates"
            label="Certificates"
            checked={@current_team.certificates_enabled}
            disabled={!@current_team.member_logins}
            phx-click="set"
            phx-value-feature="certificates"
          >
            Members send a certificate, and a team admin checks it before recording the award.
            <.needs_member_logins :if={!@current_team.member_logins} />
          </.switch>

          <.switch
            id="feature-chores"
            label="Chores"
            checked={@current_team.chores_enabled}
            disabled={!@current_team.member_logins}
            phx-click="set"
            phx-value-feature="chores"
          >
            Members log chores, and team admins accept them for hours.
            <.needs_member_logins :if={!@current_team.member_logins} />
            <.a
              :if={Team.chores?(@current_team)}
              navigate={~p"/teams/#{@current_team}/settings/chore-categories"}
            >Chore categories</.a>
          </.switch>
        </div>

        <.switch
          id="feature-travel"
          label="Travel"
          checked={@current_team.travel_enabled}
          phx-click="set"
          phx-value-feature="travel"
        >
          How members got to each incident, and the km round trip from home, on the
          incident's Travel tab. Members confirm theirs before you publish.
        </.switch>

        <.switch
          id="feature-whiteboard"
          label="Whiteboard"
          checked={@current_team.whiteboard_enabled}
          phx-click="set"
          phx-value-feature="whiteboard"
        >
          Your {@service} whiteboard, on the Dashboard and its own page.
          <.spinner :if={@reading_whiteboard?} id="whiteboard-reading" class="block">
            Reading the whiteboard from {@service}…
          </.spinner>
          <span
            :if={
              @current_team.whiteboard_enabled and !@current_team.d4h_whiteboard and
                !@reading_whiteboard?
            }
            id="whiteboard-off-in-d4h"
            class="block font-semibold"
          >
            {@service} has the whiteboard turned off for your team. Turn it on in {@service}.
          </span>
        </.switch>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :on?, :boolean, required: true
  slot :inner_block, required: true

  # A feature SAR Duty turns on: where a switch would be, whether it is on.
  defp set_by_sar_duty(assigns) do
    ~H"""
    <div id={@id} class="switch-row">
      <div class="grow">
        <span class="block font-semibold">{@label}</span>
        <span class="hint block">{render_slot(@inner_block)}</span>
      </div>
      <.badge kind={if @on?, do: :success, else: :default}>{if @on?, do: "On", else: "Off"}</.badge>
    </div>
    """
  end

  defp needs_member_logins(assigns) do
    ~H"""
    <span class="block">Turn on member logins first.</span>
    """
  end

  # Turning on makes and emails a card for each member, so it asks first, with the
  # counts, and from 10 emails up waits on a check box (send_confirm/3). Turning off
  # cancels none, so it doesn't.
  defp turn_on_cards_confirm(%Team{every_member_card: false}, %{cards: cards} = plan)
       when cards > 0 do
    plan.emails
    |> send_confirm("Turn on Every member gets a card?", cards_confirm(plan))
    |> Map.put(
      "data-confirm-button",
      Service.Format.count(cards, one: "Create %d card", many: "Create %d cards")
    )
  end

  defp turn_on_cards_confirm(_team, _plan), do: %{}

  # "Creates 40 cards and emails 38 members.", then "2 have no email." when some do.
  defp cards_confirm(%{cards: cards, emails: emails, no_email: no_email}) do
    created = "Creates #{Service.Format.count(cards, one: "%d card", many: "%d cards")}"

    emailed =
      if emails > 0,
        do: " and emails #{Service.Format.count(emails, one: "%d member", many: "%d members")}.",
        else: "."

    without =
      no_email > 0 &&
        Service.Format.count(no_email, one: "%d has no email.", many: "%d have no email.")

    Enum.filter([created <> emailed, without], & &1)
  end

  defp no_email_text(members, service) do
    count =
      members |> length() |> Service.Format.count(one: "%d member has", many: "%d members have")

    names = members |> Enum.map(& &1.name) |> Service.Format.and_list()
    "#{count} no email in #{service}, so they get a card but no email: #{names}."
  end

  # Turning off logs members out, so it asks first. Turning on doesn't.
  defp turn_off_confirm(false, _question, _body, _button), do: %{}

  defp turn_off_confirm(true, question, body, button),
    do: %{"data-confirm" => "#{question} #{body}", "data-confirm-button" => button}
end

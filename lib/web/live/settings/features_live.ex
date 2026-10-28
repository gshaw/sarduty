defmodule Web.Settings.FeaturesLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.Team
  alias App.Operation.SetTeamFeature

  # The team's features, /teams/:subdomain/settings/features: one switch each, saved when
  # flipped. Chores and certificates need member logins, so they sit under it. MCP and ID
  # cards are SAR Duty's to turn on, from /admin/teams/:id (App.Operation.SetTeamMCP,
  # App.Operation.SetTeamIdCards), so they show only as on or off. A team asks for ID
  # cards; MCP isn't offered, so it shows only once on.
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Team settings · Features", reading_whiteboard?: false)}
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

  defp message(%{member_logins: true}, :member_logins),
    do: "Member logins turned on. Members can log in now."

  defp message(_team, :member_logins), do: "Member logins turned off. Members cannot log in."
  defp message(%{chores_enabled: true}, :chores), do: "Chores turned on."
  defp message(_team, :chores), do: "Chores turned off."
  defp message(%{certificates_enabled: true}, :certificates), do: "Certificates turned on."
  defp message(_team, :certificates), do: "Certificates turned off."
  defp message(%{whiteboard_enabled: true}, :whiteboard), do: "Whiteboard turned on."
  defp message(_team, :whiteboard), do: "Whiteboard turned off."

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:features} />
    <div class="measure">
      <p class="lead">Turn on what your team uses. Each switch saves right away.</p>

      <div id="features" class="flex flex-col gap-6">
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
        </div>

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

        <.set_by_sar_duty
          :if={@current_team.mcp_enabled}
          id="feature-mcp"
          label="MCP"
          on?={true}
        >
          Team admins connect an AI agent, such as Claude Code, that reads your team's data.
          <.a navigate={~p"/teams/#{@current_team}/settings/mcp"}>MCP tokens</.a>
        </.set_by_sar_duty>

        <.set_by_sar_duty id="feature-id-cards" label="ID cards" on?={@current_team.id_cards_enabled}>
          Members add their ID card to Apple Wallet or Google Wallet. SAR Duty turns ID cards
          on. Email support@sarduty.com to ask.
        </.set_by_sar_duty>
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

  # Turning off logs members out, so it asks first. Turning on doesn't.
  defp turn_off_confirm(false, _question, _body, _button), do: %{}

  defp turn_off_confirm(true, question, body, button),
    do: %{"data-confirm" => "#{question} #{body}", "data-confirm-button" => button}
end

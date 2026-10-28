defmodule Web.Settings.FeaturesLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.Team
  alias App.Operation.SetTeamFeature
  alias App.Operation.SetTeamMCP

  # The team's features, /teams/:subdomain/settings/features: one switch each, saved when
  # flipped. Chores and certificates need member logins, so they sit under it. ID cards
  # are SAR Duty's to turn on (App.Operation.SetTeamIdCards), so they show only as on or
  # off.
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Team settings · Features", reading_whiteboard?: false)}
  end

  def handle_event("set", %{"feature" => "mcp"}, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    enabled = !team.mcp_enabled

    case SetTeamMCP.call(team, enabled, user) do
      {:ok, team} ->
        {:noreply, socket |> assign(current_team: team) |> put_flash(:info, mcp_message(team))}

      {:error, :not_allowed} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Only members with Owner or Editor access in #{socket.assigns.service} can turn MCP on or off."
         )}
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

  defp message(%{member_logins: true}, :member_logins),
    do: "Member logins turned on. Members can log in now."

  defp message(_team, :member_logins), do: "Member logins turned off. Members cannot log in."
  defp message(%{chores_enabled: true}, :chores), do: "Chores turned on."
  defp message(_team, :chores), do: "Chores turned off."
  defp message(%{certificates_enabled: true}, :certificates), do: "Certificates turned on."
  defp message(_team, :certificates), do: "Certificates turned off."
  defp message(%{whiteboard_enabled: true}, :whiteboard), do: "Whiteboard turned on."
  defp message(_team, :whiteboard), do: "Whiteboard turned off."

  defp mcp_message(%{mcp_enabled: true}), do: "MCP turned on."
  defp mcp_message(_team), do: "MCP turned off. Every token is revoked."

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

        <.switch
          id="feature-mcp"
          label="MCP"
          checked={@current_team.mcp_enabled}
          phx-click="set"
          phx-value-feature="mcp"
          {turn_off_confirm(@current_team.mcp_enabled, "Turn off MCP?", "Every token is revoked, and agents stop working right away.", "Turn off MCP")}
        >
          Team admins connect an AI agent, such as Claude Code, that reads your team's data.
          <.a
            :if={@current_team.mcp_enabled}
            navigate={~p"/teams/#{@current_team}/settings/mcp"}
          >MCP tokens</.a>
        </.switch>

        <div id="feature-id-cards" class="switch-row">
          <div class="grow">
            <span class="block font-semibold">ID cards</span>
            <span class="hint block">
              Members add their ID card to Apple Wallet or Google Wallet. SAR Duty turns ID
              cards on. Email support@sarduty.com to ask.
            </span>
          </div>
          <.badge kind={if @current_team.id_cards_enabled, do: :success, else: :default}>
            {if @current_team.id_cards_enabled, do: "On", else: "Off"}
          </.badge>
        </div>
      </div>
    </div>
    """
  end

  defp needs_member_logins(assigns) do
    ~H"""
    <span class="block">Turn on member logins first.</span>
    """
  end

  # Turning off logs members out or revokes tokens, so it asks first. Turning on doesn't.
  defp turn_off_confirm(false, _question, _body, _button), do: %{}

  defp turn_off_confirm(true, question, body, button),
    do: %{"data-confirm" => "#{question} #{body}", "data-confirm-button" => button}
end

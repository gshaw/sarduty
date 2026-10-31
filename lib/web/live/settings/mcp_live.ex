defmodule Web.Settings.MCPLive do
  use Web, :live_view_app_layout

  import Web.Components.CopyButton
  import Web.Components.TeamSettingsTabs

  alias App.Model.AgentConnection
  alias App.Operation.DisconnectAgent

  # The team's AI agents (#28, #761), /teams/:subdomain/settings/mcp: the address to
  # paste into an agent, and the agents connected. Connecting starts in the agent, which
  # sends the admin to Web.AgentAuthorizeLive. A SAR Duty admin turns Agents on and off
  # (App.Operation.SetTeamMCP). It isn't offered to teams, so while it is off this page
  # is not found.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !team.mcp_enabled, do: raise(Web.Status.NotFound)

    socket =
      socket
      |> assign(page_title: "Team settings · Agents")
      |> assign(endpoint_url: Web.OAuthController.mcp_url(team.subdomain))
      |> assign_connections()

    {:ok, socket}
  end

  defp assign_connections(socket),
    do:
      assign(
        socket,
        :connections,
        AgentConnection.get_connected_for_team(socket.assigns.current_team)
      )

  def handle_event("disconnect", %{"id" => id}, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    with {id, ""} <- Integer.parse(id),
         {:ok, connection} <- DisconnectAgent.call(team, id, user) do
      socket =
        socket
        |> assign_connections()
        |> put_flash(:info, "#{connection.name} disconnected.")

      {:noreply, socket}
    else
      _not_found ->
        {:noreply,
         socket
         |> assign_connections()
         |> put_flash(:error, "That agent is already disconnected.")}
    end
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:mcp} />
    <div class="measure">
      <p>
        Connect an AI agent, such as Claude or ChatGPT, so it can read {@current_team.name}’s
        data in SAR Duty: members, groups, activities and their attendance, hours, chores,
        qualifications, and change history.
      </p>
      <p>
        Agents only read: they cannot change anything. They never see email, phone numbers,
        or addresses. SAR Duty logs every request, and SAR Duty admins can read the log.
      </p>
      <p id="no-training" class="font-semibold">
        Connect only an agent that does not train on your chats. Personal accounts, free or
        paid, often train unless you turn it off. The agent gets your members’ names, hours,
        and history.
      </p>
      <p>
        Each connection is yours. It stops working when you disconnect it, or when you are
        no longer a team admin.
      </p>

      <h2 class="heading mt-8">Connect an agent</h2>
      <p>Paste this address into your agent. It sends you here to log in and choose Allow.</p>
      <.copy_code_block id="agent-address" value={@endpoint_url} label="Copy address" />
      <ul id="connect-steps" class="list-disc pl-6">
        <li>
          <strong>Claude</strong>
          on the web, desktop, or phone: Settings, then Connectors, then Add custom connector.
        </li>
        <li><strong>ChatGPT</strong>: Settings, then Apps & Connectors, then Create.</li>
        <li>
          <strong>Claude Code</strong>: run the command below, then <code>/mcp</code> to log in.
        </li>
      </ul>
      <.copy_code_block
        id="claude-code-command"
        value={"claude mcp add --transport http --scope user sarduty #{@endpoint_url}"}
        label="Copy command"
      />
      <p>
        Agents on your computer, such as Cursor and VS Code, work too. For another agent on
        the web, email support@sarduty.com.
      </p>

      <h2 class="heading mt-8">Connected agents</h2>
      <.empty_state :if={@connections == []} id="no-agents" title="No agents yet">
        Paste the address above into your agent to connect it.
      </.empty_state>
      <.table
        :if={@connections != []}
        id="agents"
        rows={@connections}
        row_id={&"agent-#{&1.id}"}
      >
        <:col :let={connection} label="Agent">{connection.name}</:col>
        <:col :let={connection} label="Connected by">{connection.user.email}</:col>
        <:col :let={connection} label="Connected" class="whitespace-nowrap">
          {Service.Format.date_long(connection.connected_at, @current_team.timezone)}
        </:col>
        <:col :let={connection} label="Last used" class="whitespace-nowrap">
          {last_used(connection, @current_team.timezone)}
        </:col>
        <:col :let={connection} label="">
          <.button
            id={"disconnect-agent-#{connection.id}"}
            type="button"
            size={:sm}
            variant={:danger}
            phx-click="disconnect"
            phx-value-id={connection.id}
            data-confirm={"Disconnect #{connection.name}? It stops reading right away."}
          >
            Disconnect
          </.button>
        </:col>
      </.table>
    </div>
    """
  end

  defp last_used(%AgentConnection{last_used_at: nil}, _timezone), do: "Never"

  defp last_used(%AgentConnection{last_used_at: used}, timezone),
    do: Service.Format.minutes_ago(used, DateTime.utc_now(), timezone)
end

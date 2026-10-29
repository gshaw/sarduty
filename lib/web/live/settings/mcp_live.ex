defmodule Web.Settings.MCPLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  import Web.Components.CopyButton

  alias App.Model.MCPToken
  alias App.Model.Team
  alias App.Operation.RevokeMCPToken

  # The team's MCP tokens (#28), /teams/:subdomain/settings/mcp. A SAR Duty admin turns
  # MCP on and off (App.Operation.SetTeamMCP). It isn't offered to teams, so while it is
  # off this page is not found.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !team.mcp_enabled, do: raise(Web.Status.NotFound)

    can_create = Team.managed_by?(team, socket.assigns.current_user.email, DateTime.utc_now())

    socket =
      socket
      |> assign(page_title: "Team settings · MCP tokens", can_create: can_create)
      |> assign(endpoint_url: url(~p"/teams/#{team}/mcp"))
      |> assign_tokens()

    {:ok, socket}
  end

  defp assign_tokens(socket),
    do: assign(socket, :tokens, MCPToken.get_live_for_team(socket.assigns.current_team))

  def handle_event("revoke", %{"id" => id}, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    with {id, ""} <- Integer.parse(id),
         {:ok, token} <- RevokeMCPToken.call(team, id, user) do
      socket =
        socket
        |> assign_tokens()
        |> put_flash(:info, "Token #{token.name} revoked.")

      {:noreply, socket}
    else
      _not_found ->
        {:noreply,
         socket |> assign_tokens() |> put_flash(:error, "That token is already revoked.")}
    end
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:mcp} />
    <div class="measure">
      <p>
        An MCP token lets your AI agent, such as Claude Code, read {@current_team.name}'s data
        in SAR Duty. It can read members, groups, activities and their attendance, hours,
        chores, qualifications, and change history.
      </p>
      <p>
        Agents only read: they cannot change anything in SAR Duty or {@service}. They never see
        email, phone numbers, or addresses. SAR Duty logs every request, and SAR Duty admins can read the log.
      </p>
      <p id="no-training" class="font-semibold">
        Use a token only with an AI service set not to train on your data. The token gives
        it your team members' names, hours, and history.
      </p>
      <p>
        Each token is yours. It stops working when you revoke it, or when you lose Owner or
        Editor access in {@service}.
      </p>

      <div id="mcp-on">
        <.form_actions :if={@can_create}>
          <.button
            id="token-create"
            variant={:success}
            navigate={~p"/teams/#{@current_team}/settings/mcp/new"}
          >
            Create token
          </.button>
        </.form_actions>
        <p :if={!@can_create} id="cannot-create" class="text-text-muted">
          Only members with Owner or Editor access in {@service} can create a token.
        </p>

        <h2 class="heading mt-8">Tokens</h2>
        <.empty_state :if={@tokens == []} id="no-tokens" title="No tokens yet">
          Create one to connect an agent.
        </.empty_state>
        <.table :if={@tokens != []} id="tokens" rows={@tokens} row_id={&"token-#{&1.id}"}>
          <:col :let={token} label="Name">{token.name}</:col>
          <:col :let={token} label="Owner">{token.user.email}</:col>
          <:col :let={token} label="Created" class="whitespace-nowrap">
            {Service.Format.date_long(token.inserted_at, @current_team.timezone)}
          </:col>
          <:col :let={token} label="Last used" class="whitespace-nowrap">
            {last_used(token, @current_team.timezone)}
          </:col>
          <:col :let={token} label="">
            <.button
              id={"revoke-token-#{token.id}"}
              type="button"
              size={:sm}
              variant={:danger}
              phx-click="revoke"
              phx-value-id={token.id}
              data-confirm={"Revoke the token #{token.name}? Agents that use it stop working right away."}
            >
              Revoke token
            </.button>
          </:col>
        </.table>

        <h2 class="heading mt-8">Connect an agent</h2>
        <p>
          Agents connect with the token in a header. The claude.ai and ChatGPT connectors cannot
          send one yet.
        </p>
        <h3 class="subheading mt-4">Claude Code</h3>
        <p>Run this in a terminal:</p>
        <.copy_code_block
          id="claude-code-command"
          value={claude_code_command(@endpoint_url)}
          label="Copy command"
        />
        <h3 class="subheading mt-4">Claude Desktop</h3>
        <p>
          Add this to <code>claude_desktop_config.json</code>, then restart Claude Desktop. It
          needs Node.js, and uses <code>mcp-remote</code> to send the token.
        </p>
        <.copy_code_block
          id="claude-desktop-config"
          value={claude_desktop_config(@endpoint_url)}
          label="Copy config"
        />
      </div>
    </div>
    """
  end

  defp last_used(%MCPToken{last_used_at: nil}, _timezone), do: "Never"

  defp last_used(%MCPToken{last_used_at: used}, timezone),
    do: Service.Format.minutes_ago(used, DateTime.utc_now(), timezone)

  @placeholder "YOUR_TOKEN"

  defp claude_code_command(url) do
    "claude mcp add --transport http sarduty #{url} \\\n" <>
      "  --header \"Authorization: Bearer #{@placeholder}\""
  end

  defp claude_desktop_config(url) do
    %{
      "mcpServers" => %{
        "sarduty" => %{
          "command" => "npx",
          "args" => ["mcp-remote", url, "--header", "Authorization:${SARDUTY_AUTH}"],
          "env" => %{"SARDUTY_AUTH" => "Bearer #{@placeholder}"}
        }
      }
    }
    |> Jason.encode!(pretty: true)
  end
end

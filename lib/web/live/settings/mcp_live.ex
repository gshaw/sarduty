defmodule Web.Settings.MCPLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.MCPCall
  alias App.Model.MCPToken
  alias App.Model.Team
  alias App.Operation.RevokeMCPToken

  # The team's MCP tokens (#28), /teams/:subdomain/settings/mcp: what agents are for
  # (#816), the tokens, and the reports agents checked or tried. A SAR Duty admin turns
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
      |> assign(queries: MCPCall.get_report_queries(team, 50))
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
      <p id="agents-intro">
        An AI agent, such as Claude or ChatGPT, can help you write reports. You open each
        report in SAR Duty, and it runs here, on your records.
      </p>
      <div id="agents-lists">
        <div>
          <h2 class="heading">Agents work from</h2>
          <ul class="list-disc pl-6">
            <li>The report language</li>
            <li>Your saved reports</li>
            <li>Your names for groups, qualifications, tags, and custom fields</li>
          </ul>
        </div>
        <div>
          <h2 class="heading">Stays in SAR Duty</h2>
          <ul class="list-disc pl-6">
            <li>Your members and activities</li>
            <li>Your equipment</li>
            <li>Every report's rows</li>
          </ul>
        </div>
      </div>
      <p class="action">
        <.a id="agents-how" navigate={~p"/agents"}>How agents work with SAR Duty</.a>
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
        <p>Any MCP app that can send a header can connect. It needs:</p>
        <ul id="connect-details" class="list-disc pl-6">
          <li>URL: <code>{@endpoint_url}</code></li>
          <li>Header: <code>Authorization: Bearer YOUR_TOKEN</code></li>
          <li>Transport: Streamable HTTP</li>
        </ul>
        <p class="mt-4">The claude.ai and ChatGPT connectors cannot send a header yet.</p>

        <h2 class="heading mt-8">Reports agents wrote</h2>
        <.empty_state :if={@queries == []} id="no-agent-reports" title="No reports yet">
          Each report an agent checks or tries shows here.
        </.empty_state>
        <.table
          :if={@queries != []}
          id="agent-reports"
          rows={@queries}
          row_id={&"agent-report-#{&1.id}"}
        >
          <:col :let={call} label="When" class="whitespace-nowrap">
            {Service.Format.minutes_ago(call.called_at, DateTime.utc_now(), @current_team.timezone)}
          </:col>
          <:col :let={call} label="Agent">{call.mcp_token && call.mcp_token.name}</:col>
          <:col :let={call} label="Report">
            <code class="line-clamp-2">{call.arguments["query"]}</code>
          </:col>
          <:col :let={call} label="">
            <span :if={call.error} class="hint">Needed a fix: {call.error}</span>
            <.a :if={!call.error} href={open_path(@current_team, call)}>Open</.a>
          </:col>
        </.table>
      </div>
    </div>
    """
  end

  # New report with the query the agent checked, as its own link opened it.
  defp open_path(team, call) do
    params = %{
      "query" => call.arguments["query"],
      "agent" => call.mcp_token && call.mcp_token.name
    }

    ~p"/teams/#{team}/reports/new?#{Map.reject(params, fn {_k, v} -> is_nil(v) end)}"
  end

  defp last_used(%MCPToken{last_used_at: nil}, _timezone), do: "Never"

  defp last_used(%MCPToken{last_used_at: used}, timezone),
    do: Service.Format.minutes_ago(used, DateTime.utc_now(), timezone)
end

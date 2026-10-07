defmodule Web.Admin.MCPLive do
  use Web, :live_view_app_layout

  import Web.Components.AdminTabs

  alias App.Model.MCPCall
  alias App.Model.MCPToken
  alias App.Model.Team
  alias App.Operation.SetTeamMCP

  @limit 200

  # The MCP trial (#28): which teams have it on, and every tool call agents made.
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "MCP", limit: @limit) |> assign_data()}
  end

  defp assign_data(socket) do
    assign(socket,
      teams: Team.get_all(),
      token_counts: MCPToken.count_live_by_team(),
      calls: MCPCall.get_recent(@limit)
    )
  end

  def handle_event("set", %{"team-id" => team_id, "enabled" => enabled}, socket) do
    team = Enum.find(socket.assigns.teams, &(Integer.to_string(&1.id) == team_id))
    if is_nil(team), do: raise(Web.Status.NotFound)

    {:ok, team} = SetTeamMCP.call(team, enabled == "true", socket.assigns.current_user)

    message =
      if team.mcp_enabled,
        do: "MCP turned on for #{team.name}.",
        else: "MCP turned off for #{team.name}. Its tokens are revoked."

    {:noreply, socket |> assign_data() |> put_flash(:info, message)}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">Admin</h1>
    <.admin_tabs current={:mcp} />
    <p class="mb-p max-w-3xl">
      Team admins can create MCP tokens once MCP is on for their team. Agents read
      members, attendance hours, activities, and qualifications, and change nothing.
      Turning MCP off revokes every token on the team. See <code>docs/mcp.md</code>.
    </p>
    <.table id="mcp-teams" rows={@teams} row_id={&"mcp-team-#{&1.id}"} class="mb-p2 table-striped">
      <:col :let={team} label="Team">
        <.a navigate={~p"/teams/#{team}"}>{team.name}</.a>
      </:col>
      <:col :let={team} label="MCP">
        <span :if={team.mcp_enabled} class="text-success-1">On</span>
        <span :if={!team.mcp_enabled} class="text-secondary-1">Off</span>
      </:col>
      <:col :let={team} label="Tokens">
        {Map.get(@token_counts, team.id, 0)}
      </:col>
      <:col :let={team} label="">
        <.button
          :if={!team.mcp_enabled}
          id={"mcp-on-#{team.id}"}
          type="button"
          size={:sm}
          phx-click="set"
          phx-value-team-id={team.id}
          phx-value-enabled="true"
        >
          Turn on MCP
        </.button>
        <.button
          :if={team.mcp_enabled}
          id={"mcp-off-#{team.id}"}
          type="button"
          size={:sm}
          variant={:danger}
          phx-click="set"
          phx-value-team-id={team.id}
          phx-value-enabled="false"
          data-confirm={"Turn off MCP for #{team.name}? This revokes its #{Service.Format.count(Map.get(@token_counts, team.id, 0), one: "%d token", many: "%d tokens")}."}
        >
          Turn off MCP
        </.button>
      </:col>
    </.table>

    <h2 class="heading">Calls</h2>
    <.table id="mcp-calls" rows={@calls} row_id={&"mcp-call-#{&1.id}"} class="table-striped">
      <:col :let={call} label="When (UTC)" class="whitespace-nowrap">
        {Service.Format.month_day_time_seconds(call.called_at, "Etc/UTC")}
      </:col>
      <:col :let={call} label="Team">{call.team.name}</:col>
      <:col :let={call} label="Account">
        {call.user && call.user.email}
        <.hint :if={call.mcp_token}>{call.mcp_token.name}</.hint>
      </:col>
      <:col :let={call} label="Tool">{call.tool}</:col>
      <:col :let={call} label="Arguments">{arguments(call.arguments)}</:col>
      <:col :let={call} label="Rows">
        <span :if={call.error} class="text-danger-1">{call.error}</span>
        <span :if={!call.error}>{call.row_count}</span>
      </:col>
      <:col :let={call} label="Took" class="whitespace-nowrap">
        {call.duration_ms && "#{call.duration_ms} ms"}
      </:col>
    </.table>
    <.hint :if={@calls == []}>No calls yet.</.hint>
    <.hint :if={length(@calls) == @limit}>The newest {@limit}.</.hint>
    """
  end

  defp arguments(arguments) do
    arguments
    |> Enum.sort()
    |> Enum.map_join(" · ", fn {key, value} -> "#{key}: #{value}" end)
  end
end

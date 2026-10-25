defmodule Web.Admin.MCPLive do
  use Web, :live_view_app_layout

  alias App.Model.MCPCall

  @limit 200

  # The MCP trial (#28): every tool call agents made. Each team's page, /admin/teams/:id,
  # turns it on or off (#513).
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, page_title: "MCP calls", limit: @limit, calls: MCPCall.get_recent(@limit))}
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">MCP calls</h1>
    <p class="mb-4 max-w-3xl">
      Every tool call agents made. A SAR Duty admin turns MCP on or off on each team's page.
      Agents read members, attendance hours, activities, qualifications, and change history,
      and can propose attendance changes for a team admin to send. See <code>docs/mcp.md</code>.
    </p>
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
        <span :if={call.error} class="text-danger-text">{call.error}</span>
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

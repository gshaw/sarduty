# MCP endpoint

A team's managers can connect their own AI agent to SAR Duty, which reads a few
allowlisted views of the team's data (#28). The one write is a proposal of attendance
changes, which waits for a team admin to send it. It is a trial: an admin
turns it on per team, starting with South Fraser. The use case that shaped the tools is
a quarterly check of each member's hours by activity tag against the team's attendance
policy. The policy lives in the agent's prompt, not in SAR Duty.

## Who gets in

- **The switch.** `teams.mcp_enabled`, set only by an admin on `/admin/mcp`
  ([SetTeamMCP](../lib/app/operation/set_team_mcp.ex)). Turning it off revokes every token
  on the team, so turning it back on wakes none of them.
- **Personal tokens.** A manager creates one on `/teams/:subdomain/settings/mcp`, which
  exists only while the switch is on. Creating one takes a checked box promising to use it
  only with an AI service set not to train on the manager's data; the
  `mcp_token_created` event records it. While the switch is off, team settings says to
  ask a SAR Duty admin. The token shows once; the database keeps its
  SHA-256 hash ([MCPToken](../lib/app/model/mcp_token.ex)). It belongs to a user and a
  team. An admin who doesn't manage the team can't create one, but anyone who can open
  the page can revoke any of the team's tokens.
- **Every request rechecks** the token is live, the team's switch is on, and the user
  still passes the D4H bar, `Team.managed_by?/3`
  ([AuthorizeMCPRequest](../lib/app/operation/authorize_mcp_request.ex)). Losing Owner or
  Editor in D4H ends a token's access at the next sync, within 10 minutes.
- **Bearer only**: `Authorization: Bearer sarduty_mcp_…`. The token decides the team; a
  URL naming another team gets 404. There is no `?access=` and no `MCP_ACCESS_KEY`.
  Honeybadger drops the header (`http_authorization` in `filter_keys`).

## The URL

`POST /teams/:subdomain/mcp`, following [urls.md](urls.md): it acts on one team, so the
URL names it. The subdomain is redundant with the token, which is the point: an agent
configured for the wrong team fails loudly instead of reading the token's team.
Agents' configs hold this URL, so it doesn't move.

## Protocol

Streamable HTTP with JSON responses, in [Web.MCPController](../lib/web/controllers/mcp_controller.ex).
POST one JSON-RPC message: `initialize`, `ping`, `tools/list`, or `tools/call`.
Notifications such as `notifications/initialized` get 202. GET and DELETE get 405, since
there is no event stream and no session. Batches get 400. Versions 2025-11-25,
2025-06-18, and 2025-03-26 are accepted; anything else is offered 2025-11-25. A request
with an `Origin` header from another host gets 403.

## Tools

One module per tool in [lib/app/mcp/tool/](../lib/app/mcp/tool), listed in
[App.MCP.Tools](../lib/app/mcp/tools.ex). Adding a tool is a module with the
[App.MCP.Tool](../lib/app/mcp/tool.ex) behaviour and a line in that list.

- **Read-only, except for proposals.** No tool writes to D4H. One tool,
  `propose_attendance_changes` (#216), saves a change set that waits for a team admin
  under "Proposed changes". It implements `call_as/4`, which also gets the token's user,
  and `read_only?/0` returning false, so `tools/list` drops its `readOnlyHint`. A test
  fails if anything in `lib/app/mcp/` mentions `ApplyChangeSet` or the D4H adapter. See
  [change-sets.md](change-sets.md).
- **History.** `member_history` and `activity_history` return the same entries as the
  history pages ([change-history.md](change-history.md)), without the account email of
  whoever sent a change.
- **Allowlisted fields.** Each tool builds explicit maps and lists every key it may
  return in `fields/0`; a test fails on any other key. Never email, phone, an address,
  coordinates, an activity's description, letter text, or a key.
- **Scoped.** Every query filters by the token's team, joins included.
- **Pure core.** `call/3` loads rows and hands them to a pure `build` or `summarize`,
  which the tests call directly.

Times are ISO 8601 in the team's time zone. Date ranges are `from` and `to`, both
included, in that zone.

## The call log

[CallMCPTool](../lib/app/operation/call_mcp_tool.ex) logs every `tools/call` in
`mcp_calls`: user, team, token, tool, the arguments the tool's schema declares, rows
returned or the error, and time taken. `/admin/mcp` shows the newest 200.
`PruneEventsWorker` deletes calls after 90 days. Creating and revoking tokens and the
switch are events, kept two years.

## Connecting

The token page shows the new token with a prompt to paste into any agent, which
tells it the URL, the header, and how to add the server. It also has the commands. Claude Code:
`claude mcp add --transport http sarduty <url> --header "Authorization: Bearer <token>"`.
Claude Desktop runs `npx mcp-remote <url> --header "Authorization:${SARDUTY_AUTH}"`. The
claude.ai and ChatGPT connectors need OAuth, which SAR Duty doesn't offer yet.

## Not yet

OAuth, a contacts scope, telling other managers when a token is created, paging, rate
limits, and more teams.

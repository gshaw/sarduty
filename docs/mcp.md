# MCP endpoint

A team's team admins can connect their own AI agent to SAR Duty, which reads
allowlisted views of the team's data (#28). It only reads (#627). A SAR Duty admin turns
it on for a team. The first use case was a quarterly check of each member's hours
by activity tag against the team's attendance policy; #595 widened the tools to general
work, such as sign-in sheets, hours tags before letter season, and chores. A policy lives
in the agent's prompt, not in SAR Duty.

## Who gets in

- **The switch.** `teams.mcp_enabled`, which only a SAR Duty admin turns on and off, on
  the team's admin page, `/admin/teams/:id`
  ([SetTeamMCP](../lib/app/operation/set_team_mcp.ex)), as with ID cards (2026-10-28):
  an agent reads the team's people, so SAR Duty checks the team first. Unlike ID cards,
  it isn't offered: a team sees Agents only once it is on, as a row on team settings'
  Features tab and the Agents tab. Turning it off revokes every connection on the team:
  `revoked_at` is set and the rows stay, so turning it back on wakes none of them.
- **Agents connect with OAuth** (#761), the MCP authorization spec (2025-11-25), so a
  team admin pastes one address into Claude, ChatGPT, or Claude Code and chooses Allow.
  Personal tokens, with their Create token page, setup prompt, and promise box, came
  out then, and live tokens ended; see [Connecting](#connecting).
- **Only a team admin allows.** The Allow page,
  [AgentAuthorizeLive](../lib/web/live/agent_authorize_live.ex), offers Allow only to a
  user who passes `Team.managed_by?/3`; a member is told who can connect. Anyone who can
  open the Agents tab can disconnect any of the team's agents.
- **Every request rechecks** the access token is live and unexpired, its connection
  isn't revoked, the team's switch is on, and the user still passes the D4H bar
  ([AuthorizeMCPRequest](../lib/app/operation/authorize_mcp_request.ex)). Losing Owner
  or Editor in D4H ends an agent's access at the next sync, within 10 minutes, and a
  refresh is refused too.
- **Bearer only**: `Authorization: Bearer sarduty_at_…`. The token decides the team; a
  URL naming another team gets 404. Honeybadger drops the header (`http_authorization`
  in `filter_keys`), and the token endpoint's `code`, `code_verifier`, and
  `refresh_token` by name.

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

- **Read-only** (#627). Every tool's `readOnlyHint` is true, and a test fails if anything
  in `lib/app/mcp/` mentions `ChangeSet`, a `Repo` write, the D4H adapter, `SendChores`,
  or `SaveChore`. Until 2026-10-26, three `propose_` tools saved change sets that waited
  for a team admin under Proposed changes (#216, #595). They came out: each kind needed
  its own wording, checks, and failures, chores needed a second approval, and with more
  kinds the queue would be approved without being read. Writes, if they come back, start
  from a real case and a page that does the job, which an agent can link to pre-filled;
  a person does the write there.
- **History.** `member_history` and `activity_history` return the same entries as the
  history pages ([change-history.md](change-history.md)), without the account email of
  whoever sent a change, and without standing changes: an away period's reason and dates
  are personal (#366). A changed custom field is named by its title, never its value
  (#681).
- **General tools, not one per job** (#595). An agent combines them: `get_team` first,
  then lists of members, activities, an activity's attendance (`list_attendance`), and
  hours. Statuses use the glossary's words, which change when the activity starts:
  `no_reply`, `signed_up`, `cant_make_it` before, `attended` and `absent` after. A chore
  activity's kind is `chores`, as on the Activities page. `list_members` gives each
  member's standing, never an away period's reason or dates (#366).
- **Hours, chores, and what is waiting.** `tax_credit_hours` counts with
  `CountTaxCreditHours`, as the letter does, so it can be lower than
  `attendance_summary`, which adds rows up. `list_chores` gives what a member wrote they
  did as `what_they_did`, never a decline's reason. `needs_attention` gives every item the
  team home lists for a team admin, without the page's limit.
- **Allowlisted fields.** Each tool builds explicit maps and lists every key it may
  return in `fields/0`; a test fails on any other key. Never email, phone, an address,
  an emergency contact, coordinates, an activity's description, letter text, or a key.
- **Scoped.** Every query filters by the connection's team, joins included.
- **Pure core.** `call/3` loads rows and hands them to a pure `build` or `summarize`,
  which the tests call directly.

Times are ISO 8601 in the team's time zone. Date ranges are `from` and `to`, both
included, in that zone.

## The call log

[CallMCPTool](../lib/app/operation/call_mcp_tool.ex) logs every `tools/call` in
`mcp_calls`: user, team, agent connection, tool, the arguments the tool's schema
declares, rows returned or the error, and time taken. MCP calls, `/admin/mcp`, shows the
newest 200. `PruneEventsWorker` deletes calls after 90 days. Connecting and
disconnecting agents and the switch are events, kept two years; tokens' events from
before #761 stay too.

## Connecting

Team settings, Agents (`/teams/:subdomain/settings/mcp`), shows the address to paste,
where it goes in Claude, ChatGPT, and Claude Code, and the connected agents. The agent
does the rest, as the MCP spec says:

1. **A 401 that points the way.** With no token, or a bad one, the endpoint answers
   `WWW-Authenticate: Bearer resource_metadata="…/.well-known/oauth-protected-resource/teams/:subdomain/mcp"`.
2. **Metadata.** That address (RFC 9728) names the team's MCP URL as the resource and
   `/teams/:subdomain` as its authorization server. Each team is its own server, so the
   URL always names the team. `/.well-known/oauth-authorization-server/teams/:subdomain`
   (RFC 8414) lists the endpoints below: PKCE `S256` only, the `authorization_code` and
   `refresh_token` grants, no client secrets.
3. **Registration** (RFC 7591), `POST /teams/:subdomain/oauth/register`. Agents register
   themselves, as `agent_clients` rows ([AgentClient](../lib/app/model/agent_client.ex)).
   Any `https` return address is kept, so an agent SAR Duty doesn't know reaches a page
   that names it; `javascript:`, `data:`, `file:`, plain `http` to another host, and
   fragments are refused here.
4. **Allow**, `/teams/:subdomain/oauth/authorize`. Logging in comes first when needed,
   and the login page says it's for connecting an agent. A web agent may connect only
   when its whole return address is on `AgentClient`'s list: Claude's two
   (`claude.ai` and `claude.com`, `/api/mcp/auth_callback`) and ChatGPT's. `localhost`,
   `127.0.0.1`, and `[::1]` on any port, and `vscode://` and `cursor://`, are always
   allowed: they return to the admin's own computer. Anything else gets "SAR Duty does
   not know this agent", naming its host. The list sets a web agent's name, so a fake
   one can't show as Claude; an agent on the admin's computer names itself, cut at 40
   characters. Only the name changes from one agent to the next. Allow writes an
   `agent_connections` row with a code, records `agent_connected` with
   `warning_shown`, and sends the admin back. A `resource`, when sent, must be the
   team's MCP URL.
5. **Tokens**, `POST /teams/:subdomain/oauth/token`
   ([ExchangeAgentToken](../lib/app/operation/exchange_agent_token.ex)). A code lasts 10
   minutes, works once, and needs its PKCE verifier. It trades for an access token,
   good for an hour, and a refresh token, good until 90 days without a refresh.
   Refreshing rotates: the refresh token it replaces still works for 60 seconds, so an
   agent whose answer got lost can ask again. Reuse after that is refused, not treated
   as theft; Disconnect is how an admin cuts a connection.

One row per agent ([AgentConnection](../lib/app/model/agent_connection.ex)), not one per
hourly token: team, user, agent, return address, and the code, refresh token, previous
refresh token, and access token as SHA-256 hashes. Connected agents lists the rows that
traded their code. `/register` and `/token` are rate limited by IP. The `.well-known`
addresses, `/register`, and `/token` send `Access-Control-Allow-Origin: *` and answer
preflights, since MCP Inspector runs these steps from a web page; `/authorize` is a page
and gets none. `PruneEventsWorker` deletes, each night, Allows whose code was never
traded and registrations no agent connected with, a day on.

<!-- cspell:ignore Boruta -->

Written by hand, not with a library such as Boruta: four small endpoints on one table,
and a library brings its own tables.

**Testing.** MCP Inspector runs the whole flow against a local server. The real Claude
and ChatGPT need a public address: a throwaway machine with made-up data, then one
connection from each on South Fraser.

**Why OAuth.** claude.ai, Claude Desktop and phone, and ChatGPT connect only with OAuth:
they have nowhere to paste a token. Andrew, a South Fraser team admin on Claude, is who
this is for. A personal token reaches only developer tools, so it can't be the main way
in. (2026-10-31)

## Not yet

One bearer check shared by MCP and any future API: OAuth tokens for agents and outside
apps, and personal tokens only for scripts, as a second kind of `agent_connections` row,
once someone asks. A REST read API, with OAuth for apps that run on their own servers,
once a first outside app exists. Also a contacts scope, telling other team admins when
an agent connects, paging, client ID metadata documents, and more web agents on the
list, one when a team asks.

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
  it isn't offered: a team sees MCP only once it is on, as a row on team settings'
  Features tab and the MCP tokens tab. Turning it off revokes every token on the team, so
  turning it back on wakes none of them.
- **Personal tokens.** A manager creates one on `/teams/:subdomain/settings/mcp/new`, and
  the list at `/teams/:subdomain/settings/mcp` revokes them. Both are not found while the
  switch is off. Creating one takes a checked box promising to use it only with an AI
  service set not to train on the manager's data; the `mcp_token_created` event records
  it. The token shows once, on the same page, in place of the form, so there is no second
  Create token to press. The database keeps its
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
  activity's kind is `chores`, as on the Activities page. `list_activities` gives
  `enough_at` and `full_at` beside `signed_up` (#447), SAR Duty's own numbers, null when
  unset. `list_members` gives each
  member's standing, never an away period's reason or dates (#366).
- **Hours, chores, and what is waiting.** `tax_credit_hours` counts with
  `CountTaxCreditHours`, as the letter does, so it can be lower than
  `attendance_summary`, which adds rows up. `list_chores` gives what a member wrote they
  did as `what_they_did`, never a decline's reason. `needs_attention` gives every item the
  team home lists for a team admin, without the page's limit.
- **Allowlisted fields.** Each tool builds explicit maps and lists every key it may
  return in `fields/0`; a test fails on any other key. Never email, phone, an address,
  an emergency contact, coordinates, an activity's description, letter text, or a key.
- **Scoped.** Every query filters by the token's team, joins included.
- **Pure core.** `call/3` loads rows and hands them to a pure `build` or `summarize`,
  which the tests call directly.

Times are ISO 8601 in the team's time zone. Date ranges are `from` and `to`, both
included, in that zone.

## The call log

[CallMCPTool](../lib/app/operation/call_mcp_tool.ex) logs every `tools/call` in
`mcp_calls`: user, team, token, tool, the arguments the tool's schema declares, rows
returned or the error, and time taken. MCP calls, `/admin/mcp`, shows the newest 200.
`PruneEventsWorker` deletes calls after 90 days. Creating and revoking tokens and the
switch are events, kept two years.

## Connecting

After creating a token, the page shows it once with a prompt to paste into any agent. The
prompt gives the URL and header, names Claude Code's `claude mcp add` only as an example,
and asks the agent to say which file to change when it can't add the server itself, as in
Claude Desktop. The tokens list shows the URL, header, and transport, with no per-app
commands. The claude.ai and ChatGPT connectors need OAuth, which SAR Duty doesn't offer
yet.

## Not yet

OAuth, a contacts scope, telling other managers when a token is created, paging, and
rate limits.

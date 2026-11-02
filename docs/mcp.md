# MCP endpoint

A team's team admins can connect their own AI agent to SAR Duty, and the agent helps
them write reports (#816). That is all it does. It works from how the team is
organized: the report language, the fields, the team's names for groups, qualifications,
tags, and custom fields, and its reports' queries. It never sees who is on the team or
what they did. The team admin opens the agent's link and runs the report in SAR Duty,
where the rows are. SAR data is sensitive, and this guard rail is what lets a team or an
organization say yes to agents. It only reads (#627). A SAR Duty admin turns it on for
a team.

Until #816 the agent read the records themselves: eleven tools for members, activities,
attendance, hours, chores, and history (#28, #595). They went, with no replacement that
reads records. A team admin who wants an agent to work on rows, for a newsletter say,
downloads a report's CSV and gives it to the agent.

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
  switch is off. The token shows once, on the same page, in place of the form, so there
  is no second Create token to press. The database keeps its SHA-256 hash
  ([MCPToken](../lib/app/model/mcp_token.ex)). It belongs to a user and a team. An admin
  who doesn't manage the team can't create one, but anyone who can open the page can
  revoke any of the team's tokens.
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

- `report_fields`: the language page's text (`App.Report.Language`, #803), and the
  team's names for things: groups, qualifications, tags, hours tags, and custom fields
  with what they're on.
- `list_reports`: the built-in reports, the team's own, and the lists that run on
  reports, each with its name, description, query, and saved values.
- `check_report`: checks a query against the team's fields with `App.Report.check/4`,
  which compiles it and never runs it. It gives the columns' labels and a link: New
  report, or Change report with `report_id`, with the query, name, and description in
  the URL and `agent=` the token's name. Saving from that link fills `reports.agent`.
  A mistake comes back as the editor shows it, with its line.
- `try_report`: runs a query on Coast Range SAR, the made-up team in `App.SampleRepo`
  (`App.Report.run_sample/3`), and gives back the first 50 rows as text, as the CSV
  writes them, marked `made_up`. The agent catches a wrong answer, such as no rows or a
  double count, before the team admin sees it. It never reads the token's team.

- **No records** (#816). No tool returns a member, an activity's title, a row, or a
  count from the team's records. `Web.MCPControllerTest` seeds them, with contact
  details and letter text, and checks every tool's output for each. A saved report's
  values can hold what a team admin typed, such as a member's ID; agents see those, as
  decided in #768.
- **Read-only** (#627). Every tool's `readOnlyHint` is true, and a test fails if anything
  in `lib/app/mcp/` mentions `ChangeSet`, a `Repo` write, the D4H adapter, `SendChores`,
  or `SaveChore`. The agent never saves a report: the team admin does, from its link.
- **Allowlisted keys.** Each tool builds explicit maps and lists every key it may
  return in `fields/0`; a test fails on any other key.
- **Scoped.** Every query filters by the token's team.

## The call log

[CallMCPTool](../lib/app/operation/call_mcp_tool.ex) logs every `tools/call` in
`mcp_calls`: user, team, token, tool, the arguments the tool's schema declares (cut at
2,000 characters, long enough for a query), items returned or the error, and time taken.
MCP calls, `/admin/mcp`, shows the newest 200. `PruneEventsWorker` deletes calls after 90
days. Creating and revoking tokens and the switch are events, kept two years.

The team's MCP tokens tab lists the last 50 queries its agents checked or tried, as
Reports agents wrote (#816): when, the token's name, the query, and Open, a New report
link with the query, or the mistake it needed fixed. The tab opens with what agents are
for and what stays in SAR Duty, and links to `/agents`, a public page that says the same
for teams and organizations deciding about agents.

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

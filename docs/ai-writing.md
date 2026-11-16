# AI writing

A team admin describes a report in plain words, and SAR Duty asks Claude to write its
query. Claude works from the report language and the team's names for things, checks
its query with SAR Duty's tools, and SAR Duty puts the answer in the editor. The rows
come from the editor's preview, in SAR Duty, after Claude is done. Claude never sees a
member, a row, or a count, and only the admin saves. Forms come next, the same way.

It replaces the MCP endpoint ([mcp.md](mcp.md)) for writing reports: connecting an agent
was too hard for most team admins. MCP goes once this works on South Fraser.

## The box

On New report and Change report, above the form, for a user AI writing is open to
([Web.ReportFormLive](../lib/web/live/report_form_live.ex)).

- "Describe it" and Write it; after the first ask, "Describe a change" and Change it.
- The query folds to one line, since AI writes it: Show query opens it, Hide query folds
  it again, and a mistake in it opens it. The preview's count drops "runs as you type"
  while it's folded.
- The ask runs in `start_async` and goes to the top of **This visit** at once, with a
  spinner naming its step (Writing…, Checking it…, Trying it on made-up data…) and Stop.
- The answer fills the query, and a new report's name, as typing would, so the preview
  reruns. AI's one-line note shows under the ask in This visit.
- This visit lists the asks, newest first, in the page only. Undo puts back the query
  and name from before an ask and drops the asks after it. An ask that changed nothing
  has no Undo. A reload loses the list.
- A failed ask is a toast, and its words go back in the box to try again.
- Save notes the version came "from the AI's draft" (`reports.agent` is `AI`).
- When nothing answers the ask, the query stays and the note says what would work.

## One ask

[App.Operation.AskAI](../lib/app/operation/ask_ai.ex) runs it, and
[App.AI.ReportJob](../lib/app/ai/report_job.ex) says what it sends.

1. **Checks first**: AI writing is open to the user, the key is set, the team has asks
   left today, and this month's asks cost less than the budget. Otherwise Claude isn't
   called and nothing is recorded.
2. **The request** (`AskAI.request/3`): the rules and the language, then the team's names
   for groups, qualifications, tags, hours tags, and custom fields, each a cache
   breakpoint; then the report as it stands and the ask. Effort medium, thinking left to
   the model, `inference_geo: "us"`, and the answer as JSON: query, name, note.
3. **Tools**: `check_report` compiles a query against the team's fields without running
   it; `try_report` runs it on Coast Range SAR, the made-up team, and gives back its
   rows. Both in [lib/app/ai/tool/](../lib/app/ai/tool).
4. **The answer** is checked again with `App.Report.check/4`. A mistake goes back to
   Claude once, unseen; a second keeps the query as it was and shows the mistake.
5. At most 6 requests per ask. Each ask starts fresh: no conversation is kept, since the
   query is the state.
6. **The row**: every ask that reached Claude is an `ai_asks` row (below).

There is no server-side refusal fallback. Its rules for replaying a fallback in the
middle of an answer don't fit this loop, and report queries rarely trip a refusal. A
refused ask says so and changes nothing.

## What Claude gets, and never gets

Gets: the language (`App.Report.Language`, the text of `/agents/reports`), the team's
name and its names for things, the report's query, name, and description, the ask, and
the tools' answers: column labels, a compiler mistake, or Coast Range SAR's made-up rows.

Never: a member, an activity, a row or a count from the team's records, contact details,
letter text, or another team. Tests hold this:

- `App.AI.ReportJobTest` seeds a team with members, contact details, and activities,
  builds the request, and checks it for each seeded value.
- `App.AI.ToolsTest` fails if a file in `lib/app/ai/` runs a query on the team
  (`Report.run(`, `Report.page`, `Report.ids`, the runner) or writes anything (a change
  set, a Repo write, D4H).

## Settings

Adminland › AI writing, `/admin/ai` ([Web.Admin.AILive](../lib/web/live/admin/ai_live.ex)),
one `ai_settings` row ([App.Model.AISettings](../lib/app/model/ai_settings.ex)). Each save
is an `ai_settings_changed` event.

- **Who gets it**: Nobody, SAR Duty admins only (to try it on a team first), or Every
  team admin. Off with no row.
- **Model**: Claude Sonnet 5.5 by default, or Opus 5.5 or Haiku 5.5. Prices are in
  [App.AI.Models](../lib/app/ai/models.ex), Anthropic's list prices on 2026-11-15.
- **Monthly budget**: $50 by default. Once this month's asks cost that much, asks stop
  for every team and the box says AI writing is paused until next month. The Claude API
  stops too when the plan's credit is spent.
- **100 asks a team a day**, reports and forms together, in `AskAI`.

Months and days are BC time.

## Usage

`ai_asks` ([App.Model.AIAsk](../lib/app/model/ai_ask.ex)), a row per ask: team, user,
kind, the ask's words, model, tokens in, cache written, cache read, and out, the cost in
millionths of a dollar from the model's price, requests, time taken, and how it ended
(used, nothing changed, failed SAR Duty's checks, declined, failed). The words are
`redact: true` and `PruneEventsWorker` clears them after 90 days; the numbers stay. Delete
team deletes a team's rows. A stopped ask leaves no row.

Adminland › AI writing shows this month's cost against the budget, the cost by team and
by person, and the newest 50 asks. Teams never see dollars. Adminland › Integrations
tests the key with a few tokens.

## Caching, later

The default 5-minute cache is all there is for now. Asks come in bursts, so asks a few
minutes apart read the language from cache and only a burst's first ask pays full
price. Warming the cache when the editor opens, the 1-hour cache, and a shorter language
for the model wait for a month of `ai_asks` cache numbers.

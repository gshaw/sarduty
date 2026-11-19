# AI writing

A team admin describes a report in plain words, and SAR Duty asks Claude to write its
query. Claude works from the report language and the team's names for things, checks
its query with SAR Duty's tools, and SAR Duty puts the answer in the editor. The rows
come from the editor's preview, in SAR Duty, after Claude is done. Claude never sees a
member, a row, or a count, and only the admin saves. Forms come next, the same way.

It replaced connecting an AI agent through MCP (#1087): connecting one was too hard for
most team admins. See [Before AI writing](#before-ai-writing-mcp).

## The box

On New report and Change report, for a user AI writing is open to
([Web.ReportFormLive](../lib/web/live/report_form_live.ex)).

- **AI writing** is a column beside the report, where the help column was; under
  1024px it sits above the report. In it, the asks as a conversation, oldest first, then
  "Describe a change" and Change it, then what AI sees and How agents work with SAR Duty.
  AI suggests no next asks: every ask is one someone typed.
- The query is hidden, since AI writes it: Show query and Hide query toggle it, and a
  mistake in it opens it. With the query, the fields are buttons under it, with How to
  write a report, What each chart takes, and What each field means. The preview's count
  drops "runs as you type" while the query is hidden.
- The ask shows at once, with the step under it (Writing…, Checking it…, Trying it on
  made-up data…) and Stop. The box clears and Change it waits until AI answers.
- The answer fills the query, and a new report's name and description, as typing
  would, so the preview reruns. AI's one-line note is its reply under the ask, with
  Undo when it changed the report.
- Undo puts back the query, name, and description from before an ask and drops the
  asks after it. The conversation is in the page only: a reload loses it.
- Stop and a failed ask are a toast, and the ask's words go back in the box to change
  and send again. A stopped ask still counts (below).
- Save notes the version came "from the AI's draft" (`reports.agent` is `AI`).
- When nothing answers the ask, the query stays and the note says what would work.

**A blank New report** starts with the box alone: "Describe the report you want", two
example asks as plain text, and Write it. Under it, five built-in reports to start from
(`App.Report.BuiltIn.starters/1`), each a copy in the editor that spends no ask, the
charts marked with Lucide's chart icons, then All N built-in reports and Write the query
yourself. The first ask that changes the report, or Write the query yourself, opens the
editor.

**The History line.** With AI writing open, What changed goes from Change report. A few
seconds after Save, `WriteHistoryLineWorker` asks Claude to compare the version before
with the one saved ([App.Operation.WriteHistoryLine](../lib/app/operation/write_history_line.ex),
[App.AI.HistoryLineJob](../lib/app/ai/history_line_job.ex)): the two names,
descriptions, and queries, no tools, effort low. So the line covers every ask, any
typing, and any Undo. It counts toward the monthly budget, never the 100 asks a day.
With AI writing off or paused, the admin types What changed (optional), as before, and
an empty one stays empty.

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
   first 50 rows as the CSV writes them. Its answer lists Coast Range SAR's groups,
   qualifications, tags, and custom fields, one of every type: a query that names the
   team's own, such as Wilderness First Aid for First aid, finds nothing there, so
   Claude tries with Coast Range's names and answers with the team's. Both in
   [lib/app/ai/tool/](../lib/app/ai/tool).
4. **The answer** is checked again with `App.Report.check/4`. A mistake goes back to
   Claude once, unseen; a second keeps the query as it was and shows the mistake.
5. At most 6 requests per ask. Each ask sends the report as it stands, with the visit's
   earlier asks and AI's notes in its prompt, oldest first. Only the words go back: the
   query is the state.
6. **The row**: every ask that passed the checks is an `ai_asks` row (below), written
   as it starts, as stopped, and updated as each request returns. The end sets how it
   ended. Stop kills the ask's task, so its row stays stopped with what it spent.

There is no server-side refusal fallback. Its rules for replaying a fallback in the
middle of an answer don't fit this loop, and report queries rarely trip a refusal. A
refused ask says so and changes nothing.

## What Claude gets, and never gets

Gets: the language (`App.Report.Language`, the text of `/agents/reports`), the team's
name and its names for things, the report's query, name, and description, the visit's
earlier asks and AI's notes, the ask, and
the tools' answers: column labels, a compiler mistake, or Coast Range SAR's made-up rows.

Never: a member, an activity, a row or a count from the team's records, contact details,
letter text, or another team. SAR data is sensitive, and this is what lets a team or an
organization say yes to AI. Tests hold this:

- `App.AI.ReportJobTest` seeds a team with members, contact details, and activities,
  builds the request, and checks it for each seeded value.
- `App.AI.ToolTest` seeds the same, calls each tool, and checks its answer for each
  seeded value, and that it holds only the keys on that tool's list. A tool builds its
  answer from explicit maps. try_report's rows are Coast Range SAR's, marked `made_up`.
- `App.AI.ToolsTest` fails if a file in `lib/app/ai/` runs a query on the team
  (`Report.run(`, `Report.page`, `Report.ids`, the runner) or writes anything (a change
  set, a Repo write, D4H). A reply that hung on the team's rows would let Claude learn
  about the team one yes-or-no question at a time (#834).

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
- **100 asks a team a day**, reports and forms together, in `AskAI`. History lines
  don't count.

Months and days are BC time.

## Usage

`ai_asks` ([App.Model.AIAsk](../lib/app/model/ai_ask.ex)), a row per ask: team, user,
kind (`report`, or `history_line` with the report's name as its words), the ask's
words, model, tokens in, cache written, cache read, and out, the cost in millionths of
a dollar from the model's price, requests, time taken, and how it ended (used, nothing
changed, failed SAR Duty's checks, declined, failed, stopped). The words are
`redact: true` and `PruneEventsWorker` clears them after 90 days; the numbers stay.
Delete team deletes a team's rows.

Adminland › AI writing shows this month's cost against the budget, with asks and History
lines counted apart ("3 asks, 1 History line"), the cost by team and by person, whose
Asks columns leave History lines out, and the newest 50 rows. Teams never see dollars. Adminland › Integrations
tests the key with a few tokens.

## Caching, later

The default 5-minute cache is all there is for now. Asks come in bursts, so asks a few
minutes apart read the language from cache and only a burst's first ask pays full
price. Warming the cache when the editor opens, the 1-hour cache, and a shorter language
for the model wait for a month of `ai_asks` cache numbers.

## Before AI writing: MCP

From #28 to #1087 (2026-10-08 to 2026-11-16), a team admin could connect their own AI
agent, such as Claude or ChatGPT, to `/teams/:subdomain/mcp` with OAuth (#761), once a
SAR Duty admin turned Agents on for the team. Its tools gave the report language, the
team's names for things, its reports' queries, and check_report and try_report, which AI
writing kept. check_report's link opened New report with the query, and the editor
followed the agent's live draft (#834). Gerry couldn't connect Coast Range SAR's agent
himself on 2026-11-15, and MCP went once AI writing worked.

What stays: the rules above, which MCP's tests held first (#627, #816); the events for
turning Agents on and off, connecting and disconnecting, and the older `mcp_token_*`
kinds, kept two years; and `reports.agent` on old versions, which names the agent whose
draft it was ("from Claude's draft"). New saves set it only for AI writing. An agent
still configured with the old address gets a 404. Scripts and outside agents still read
the `/agents` pages, and `/agents/reports` is AI writing's prompt.

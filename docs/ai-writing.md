# AI writing

A team admin describes a report in plain words, and SAR Duty asks Claude to write its
query. Claude works from the report language and the team's names for things, checks
its query with SAR Duty's tools, and SAR Duty puts the answer in the editor. The rows
come from the editor's preview, in SAR Duty, after Claude is done. Claude never sees a
member, a row, or a count, and only the admin saves. A team's form is written the same
way, from the agency's PDF ([Forms](#forms)).

It replaced connecting an AI agent through MCP (#1087): connecting one was too hard for
most team admins. See [Before AI writing](#before-ai-writing-mcp).

## The box

On New report and Change report, for a user AI writing is open to
([Web.ReportFormLive](../lib/web/live/report_form_live.ex)).

- **The page** (`ai_editor` in Web.Components.AIWriting, the same on Change form): the
  title, the description, and the page's links, Rename and Show query; AI writing beside
  them; the report under them; and a bar stuck to the window's foot with Not saved yet,
  Save report, and Cancel.
- **AI writing** starts beside the title. From 1024px it stays in view as the page
  scrolls, filling the window down to the bar (assets/js/ai_panel.js), and its
  conversation scrolls on its own, to the newest reply after each ask. Under 1024px
  it's one column, title first, and the conversation shows its last two asks with Show
  earlier asks. In it: what AI sees, one line with How it works; the asks as a
  conversation, oldest first; then "Ask AI" with its hint, "A change, or a question
  about the report.", and Ask.
- **Rename** opens a dialog with the name and description, inside the form: Rename
  keeps them, to save with Save report, and Cancel or Escape puts them back. With AI
  writing off or the query written by hand, the fields show on the page as before.
  Under the newest reply, **Try next**: two or three asks AI suggests, to show what it
  can do. A tap puts one in the box; it never sends on its own. Every ask is still one
  someone sent.
- The query is hidden, since AI writes it: Show query and Hide query toggle it, and a
  mistake in it opens it. With the query, the fields are buttons under it, with How to
  write a report, What each chart takes, and What each field means. The preview's count
  drops "runs as you type" while the query is hidden.
- **Not saved yet** shows beside Save report or Save form once the page differs from
  what's saved (Web.Components.Unsaved). Leaving then asks first: a reload or closing
  the tab through the browser's own question, a link through a confirm. Save and Cancel
  never ask.
- **Enter sends** the ask, and Shift+Enter starts a new line (assets/js/ask_enter.js).
  On a touch screen, return starts a new line and Ask sends, and the hint saying so
  hides.
- The ask shows at once, with Thinking… and the seconds it has taken under it, and
  Stop. One steady line: an ask's own steps (writing, checking, trying) change too fast
  to read. The box clears and Ask waits until AI answers.
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

## Forms

An admin writes a form from the agency's PDF (#1089) when AI writing is open to them:
a team's admins their team's own, on a team with team forms on
([documents.md](documents.md#a-teams-own-forms)), and an organization's admins its
forms for every team in it. The pages are one set for both (Web.FormOwner). An
organization's form is tried on Coast Range SAR, and AI gets the custom fields every
team in the organization has, never a team's own groups or tags.

- **New form** (Team settings › Forms, or an organization's Forms,
  [Web.FormStartLive](../lib/web/live/form_start_live.ex))
  takes the name, the agency's PDF, and What it's for (optional), "When it's filled in
  and who signs it." With AI writing open, its button is Write form. It saves the form
  off with no text, as before, and opens Change form with What it's for as the first
  ask, already running, or "Write this form." without it. The ask goes in the flash, so
  a reload of Change form never asks again.
- **Change form**, `/teams/:subdomain/settings/forms/:id/edit`
  ([Web.FormChangeLive](../lib/web/live/form_change_live.ex)), linked from the form's
  page: the draft tried on one of the team's activities it shows on, marked SAMPLE, as
  Try it prints it, every page a picture, is the main column, with Tried on to pick
  another and Open activity at the label's end, in a new window, to check the form
  against it. Before there's a text, it's the agency's blank form. AI writing is the column
  beside it, as on Change report: the conversation, the box, and the hint, "AI works only
  with the agency's blank form, the form language, and your team's field names."
- The running ask is Thinking…, as for reports. Stop and a failed ask are a toast, and the ask's words go back in the box, as for reports.
- **AI's reply** is its note, then **Left blank**: each label on the page it didn't
  fill, and why. Ask for one in the box, or leave it. Undo puts back the text from
  before an ask.
- **Two ways past AI writing**, the page's links under the title:
  - **Show how it fills in** opens the text, "How it fills in", for a small fix by
    hand, as Show query does on a report. Each change runs the checks saving runs
    (`SaveForm.check_for/5`); a mistake shows under it and keeps it open, and once it
    passes the try reprints. Nobody writes a form by hand from nothing.
  - **Replace PDF** opens a dialog for the agency's new PDF. It takes the page's place
    and asks AI to "Fit the form to the agency's new PDF." The try prints on it at once.
    Undo, Stop, or a failed ask puts the old PDF back, and Save form saves the PDF with
    the text. A scan is refused in the dialog.
- **Save form** saves the text (App.Operation.SaveForm) and keeps the form's state, so a
  new form stays off until a team admin turns on testing. Nothing is saved until then,
  a reload loses the conversation, and forms have no History line.

[App.AI.FormJob](../lib/app/ai/form_job.ex) says what one ask sends, run by `AskAI` with
kind `form`:

- **Cached first**: the rules and the form language (`App.Document.language/0`, the
  text of [documents.md](documents.md)) with the report language its queries use, then
  the team's names for things, as a report's ask has them. Each is a cache breakpoint.
- **Then**: the PDF as a document block, the agency's blank form, never a filled one,
  and its page's measures (`Service.PDFGeometry.describe/1`), cached together as the
  third breakpoint; then the visit's earlier asks and replies, the form's text as it
  stands, and the ask.
- **The tool**: `check_form(text)` ([App.AI.Tool.CheckForm](../lib/app/ai/tool/check_form.ex))
  runs `SaveForm.check_for/5`: every check saving runs, saving nothing, reading no
  records. It answers with the text's questions and places, or the mistake.
- **The answer** is `{text, note, blank: [{label, why}]}`, checked once more with
  `check_for`. A mistake goes back once, unseen; a second keeps the form as it was and
  shows the checker's line.
- **The try** runs after, in SAR Duty (App.Operation.TryForm), on one of the team's
  activities. That activity never reaches Claude.
- **It streams under the hood**: a first draft with the PDF can take a minute or more,
  near the adapter's 120-second timeout, so the request streams and the timeout is
  between pieces (`App.Adapter.Claude.assemble/1`). Nothing streams to the page.
- The limits are a report's: 100 asks a day, reports and forms together, for each team
  and each organization apart, and the monthly budget.

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
  builds the request, and checks it for each seeded value. `App.AI.FormJobTest` does
  the same for a form's ask and check_form's answers, with an incident to try it on.
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

- **Suggest next asks on reports** and **on forms**: whether AI gives Try next after
  each reply (`AISettings.suggest?/2`). Both start on. Off, `AskAI` doesn't ask for
  them, so the answer is a little shorter.
- **Who gets it**: Nobody, SAR Duty admins only (to try it on a team first), or Every
  team and organization admin. Off with no row.
- **Model**: Claude Sonnet 5.5 by default, or Opus 5.5 or Haiku 5.5. Prices are in
  [App.AI.Models](../lib/app/ai/models.ex), Anthropic's list prices on 2026-11-15.
- **Monthly budget**: $50 by default. Once this month's asks cost that much, asks stop
  for every team and the box says AI writing is paused until next month. The Claude API
  stops too when the plan's credit is spent.
- **100 asks a day**, reports and forms together, for each team and each organization,
  in `AskAI`. History lines don't count. An organization's asks are its own rows
  (`ai_asks.organization_id`), apart from its teams'.

Months and days are BC time.

## Usage

`ai_asks` ([App.Model.AIAsk](../lib/app/model/ai_ask.ex)), a row per ask: team, user,
kind (`report`, `form`, or `history_line` with the report's name as its words), the ask's
words, model, tokens in, cache written, cache read, and out, the cost in millionths of
a dollar from the model's price, requests, time taken, and how it ended (used, nothing
changed, failed SAR Duty's checks, declined, failed, stopped). The words are
`redact: true` and `PruneEventsWorker` clears them after 90 days; the numbers stay.
Delete team deletes a team's rows.

Adminland › AI writing shows this month's cost against the budget, with asks and History
lines counted apart ("3 asks, 1 History line"), the cost by team or organization and
by person, whose
Asks columns leave History lines out, and the newest 50 rows, each naming its kind,
report or form. Teams never see dollars. Adminland › Integrations
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

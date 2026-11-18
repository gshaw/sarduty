# Review

What a reviewer of a SAR Duty PR looks for beyond [AGENTS.md](AGENTS.md). Bunter reads
this file, AGENTS.md, and the shared checklists named below on every review.

- checks: web, elixir
- design: `/styles` (`lib/web/controllers/style_guide_html/`), `assets/css/`, and
  `lib/web/components/`
- writing: [docs/writing.md](docs/writing.md)

## Leave to CI

A test or Credo already fails on these, so a review never reports them. If one gets past
CI, the finding is that its test has a gap.

- Design tokens, the spacing scale, and colour classes: `Web.DesignSystemTest`.
- Standard table columns and columns that stay put: `Web.StandardColumnsTest`,
  `Web.TableFitTest`.
- Feature code reached from shared code: `App.FeatureReachTest`.
- D4H writes outside `ApplyChangeSet`, and attendance read from `status`: the change set
  and attendance tests.
- Personal fields without `redact: true`: `App.Model.RedactFieldsTest`.
- A number and its unit written by hand: `test/service/format_usage_test.exs`.
- A file store key built by hand, and a job queued outside its worker's `enqueue`.
- A team page with no search kind or `not_searched/0` reason.
- MCP tools that read records, inline scripts, and the CSP.
- "D4H" written into text, Actions order and names, a form with no Cancel or no
  `phx-submit`, a heading row built by hand, and a link ending in a space.
- `String.to_atom/1`, deprecated LiveView calls, and HEEx syntax: Credo and the compiler.

## Look hard at these

AGENTS.md rules that no test checks. A miss here only a reviewer catches.

- **Team scoping.** Every table in a team query filters `team_id`, joins and deletes
  included, and a record is fetched through the current team before it changes.
- **Retiring and not-a-person members.** A new query that counts, contacts, or lets
  members in starts from `Member.counted_query/1`, `not_retiring_query/1`, or
  `managers_query/2`.
- **D4H ids and local ids.** Route params and foreign keys are local ids; only D4H calls
  take a `d4h_*_id`.
- **One home per rule.** A page that works a rule out itself, rather than asking the
  operation or model that owns it.
- **Side effects in Operations.** A `handle_event` that writes, sends, or calls an
  adapter directly.
- **Jobs.** Job or inline per [docs/jobs.md](docs/jobs.md), the job inserted in the same
  transaction as its row, and a failed send that returns `{:error, reason}`.
- **Members on team pages.** A page opened to members lists only the events they may
  send in `view_events` and `member_events`.
- **Credentials and personal data.** A new secret uses `EncryptedString`; personal data
  stays plain with `redact: true`.
- **Times.** Stored in UTC, shown in the team's zone through `Service.Format`.
- **Components first.** Utilities where a component or class exists, a `.card` that
  isn't a tile or a set-apart result, and an email or phone number people use that isn't
  `<.email>` or `<.phone>`.
- **A confirm for many records** follows `/styles/confirm-dialog#many`.
- **Tests.** An operation's tests call its pure function, LiveView tests target ids, and
  a test file mirrors its `lib/` path.
- **CHANGELOG.md.** A PR a team will notice adds its line under this week's heading.

## Text

Any changed text a person reads goes through the checklist in
[docs/writing.md](docs/writing.md#checklist). Only naming D4H and writing units have
tests; the rest is judgment. Read it in the reader's place: a tired volunteer on a
phone. Glossary terms, words to avoid, sentence length, sentence case, and buttons that
name a verb and an object are the usual misses.

## Needs the app running

These wait for the verify step (gshaw/bunter#6), so a code review flags them only when
the diff alone shows the problem: the narrow layout at phone width, dark mode, focus
order after a dialog or a `patch`, and the style guide page a new component needs.

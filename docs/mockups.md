# Mockups

<!-- cspell:ignore CRSAR Kowal Priya VSAR -->

A design proposal on an issue is shown with mockups, and a finished feature on its PR with
marked screenshots. Both are made with [redline](https://github.com/gshaw/redline), Gerry's
mockup kit for every project, in `~/Developer/redline`. Every round looks the same and
reads in seconds: real pages from the app, with what changes marked in fuchsia and
numbered. Plain screenshots only when someone asks for them, and those are PNG too,
through `mise exec -- oxipng -o 2 --strip safe <file>`.

redline's [README](https://github.com/gshaw/redline#readme) holds the marks, pins,
labels, frames, crops, diagrams, the review page, and posting. This page holds what is
SAR Duty's own: the dump, the cast, widths, and words. The kit started here
(#741, 2026-10-29) and moved to redline on 2026-11-13 (#1069).

## SAR Duty's rules

On top of redline's rules:

1. **Draw on the real app.** Every screen starts as a real page, dumped from this checkout
   with the made-up cast, and the proposal is spliced in. Never redraw a page by hand, and
   never draw a card that stands in for one. What the app can't render (a text thread, an
   email in a mail app) uses redline's `sms()` and `mail()` frames.
2. **One cast.** Coast Range SAR (CRSAR; legal name Coast Range Search and Rescue Society),
   team admin Alex Chen, member Cameron Ruiz, and the cast in
   [App.CoastRange](../lib/app/coast_range.ex): a year of activities, attendance,
   groups, qualifications, equipment, and chores. It is the team agents' reports run on
   too ([reports.md](reports.md#coast-range-sar)). Each member stands for one case, such
   as Dana Kowal for Away and Drew Patel for an expired award: its moduledoc's "Who to
   use" says who, and a test keeps it true. A dump test picks the records it shows from
   the cast by that list, such as `MockupSeed.activity(cast, "Missing hiker")`, rather
   than making its own; it adds only what the cast lacks, and a new case gets a new
   member. A second team is Valley SAR (VSAR), for mockups only. Phone numbers are
   604-555-01xx; SAR Duty's own number is 604-555-0100. Never a real person, team, or
   number: issues are public.
3. **Desktop first, phones for phone tasks.** Desktop at 1280 (1024 for a narrow settings
   page), phones at 390 in an iPhone frame. iPad means the mini, at 744×1133.
4. **Words follow [writing.md](writing.md).** Mock copy is proposed copy: glossary words,
   short sentences, values as `Service.Format` writes them.
5. **Light mode.** The browser frame shows the page's real URL: `shots.json` sets
   `"host": "sarduty.com"`, and each shot its `url`.

## A round

A round lives in `tmp/mockups/<topic>/`, which git ignores. Start from the example: a
switch on Account settings, the text on a phone, and two diagrams.

```sh
mkdir -p tmp/mockups && cp -R tools/mockups/example tmp/mockups/<topic>
tools/mockups/app-css.sh                                  # today's CSS and fonts
tools/mockups/dump.sh tmp/mockups/<topic>/dump_test.exs   # real/*.html
redline all tmp/mockups/<topic>                           # pages, shots, review, body
```

`redline` is `~/Developer/redline/bin/redline`, on PATH through `~/.local/bin`. It runs
on its own pinned node, Python, oxipng, and Puppeteer, so this repo needs none of them
for mockups.

| File            | What                                                                       |
| --------------- | -------------------------------------------------------------------------- |
| `dump_test.exs` | Seeds the cast, picks its records, adds only what it lacks, and dumps it.  |
| `build.py`      | Splices the proposal into `real/` pages and writes one page per shot.      |
| `shots.json`    | Each shot's `id`, `page`, `title`, `lead`, `pins`, and its frame and crop. |
| `intro.html`    | The review page's Overview tab: verdict, what changed, open questions.     |
| `lead.md`       | The issue's or PR's words, put at the top of `body.md`.                    |

`dump_test.exs` calls `MockupSeed.team()` and ends with `MockupSeed.dump/1`, which writes
to `real/`. The cast it returns has each member by name (`cast["Priya Nair"]`), and every
row by kind and key in `cast.rows`; `MockupSeed.activity(cast, title)` is the latest
activity with that title. It dumps LiveViews and controller pages, such as the style
guide, alike. `dump.sh` copies the test into `test/mockups/` for the run only. Times the
seed makes change every run, so splice around them with `cut(s, start, end, new)`, not
`sub` on the exact text.

`build.py` starts with `from sarduty import *` and `m = SarDuty(__file__)`.
[sarduty.py](../tools/mockups/sarduty.py) is SAR Duty's adapter: the app's CSS, the
LiveView clean-up, and the app's pieces as its components render them (`btn`, `link`,
`banner`, `warning`, `hint`, `switch`, `table`, `checkbox`, `marker`). Everything else,
from `sub` and `mark` to `sms`, `diagram`, and `flow`, is redline's.

| File                                      | What                                                |
| ----------------------------------------- | --------------------------------------------------- |
| [sarduty.py](../tools/mockups/sarduty.py) | `SarDuty` rounds and the app's pieces.              |
| [dump.sh](../tools/mockups/dump.sh)       | Dumps a round's pages with its dump test.           |
| [app-css.sh](../tools/mockups/app-css.sh) | Builds the app's CSS and fonts for `file://` pages. |
| [example/](../tools/mockups/example)      | The round to copy.                                  |

[Web.MockupSeedTest](../test/web/mockup_seed_test.exs) seeds the cast and dumps two
pages, so a change that breaks the dump fails in CI rather than in the next round.

## Showing and posting

Show `review.html` inline for review (in T3 Code, `html_preview` then `html_render`),
never as a Claude Artifact. Once a design is picked, write the Overview's words in
`lead.md` and post the round from this checkout:

```sh
redline body tmp/mockups/<topic>
redline post tmp/mockups/<topic> issue <n>
```

It uploads the shots, makes phone shots 320 wide, and saves `posted.md`. Later edits
start from `posted.md`, never from `body.md`.

## Screenshots on a PR

A PR for something people see shows it with marked shots: the PR branch's real pages,
dumped and marked with what changed. Nothing is spliced in: `build.py` only marks it
(`mark(s, '<section id="x"', 1)`), and splices back what the PR removed as
`removed(html, pin)`. One marked shot replaces a before-and-after pair. No review page:
`lead.md` says what the PR does, then `redline post tmp/mockups/<topic> pr <n>`, or
`pr new --title "…"` to open it. Captions say what changed for the person using the page,
in the PR's words: "**New.** Text reminders, one switch per team."

## Gotchas

- `mark()` keeps the element's own width; pass `hug=True` to shrink it to its content. A
  bare `new()` hugs; one given a `cls`, such as `mt-4`, keeps the width its class sets.
- A pin at a narrow page's left edge falls off the screen: `right="inset"` pulls it
  inside, and `right=True` puts it on the right corner. In a table, `right="in"`.
- The dump logs every query: `tools/mockups/dump.sh … | grep -E "Result|was not dumped"`.
- `app-css.sh` rewrites `/fonts/` to `fonts/` so file:// pages load IBM Plex.
- LiveView's reconnect toasts are dropped by `SarDuty.page`; a page with other hidden
  elements that show without the app's JS needs them removed in `build.py`.

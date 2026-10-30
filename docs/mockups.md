# Mockups

<!-- cspell:ignore CRSAR VSAR -->

A design proposal on an issue is shown with mockups made by the kit in
[tools/mockups/](../tools/mockups). Every round looks the same and reads in seconds: real
pages from the app, with what changes marked in fuchsia and numbered.

## The rules

1. **Draw on the real app.** Every screen starts as a real page, dumped from this checkout
   with the made-up cast, and the proposal is spliced in. Never redraw a page by hand, and
   never draw a card that stands in for one. What the app can't render (a text thread, an
   email in a mail app) uses the kit's frames.
2. **Mark only what changes, in fuchsia.** The app never uses fuchsia, so a mark can't be
   mistaken for design. Three kinds:
   - **New**: dashed outline with a faint fill. `new(html, pin)`
   - **Changed**: dotted outline, no fill. `changed(html, pin)`, or
     `mark(s, '<li id="x"', pin, "changed")` on an element already in the page
   - **Removed**: thin outline, faded, struck through. `removed(html, pin)`
3. **Every mark gets a numbered pin, and every pin a caption.** Captions live in
   `shots.json`, start with the kind in bold ("**New.**"), and say what it does or why in
   one sentence. Numbers restart on each shot. One pin may mark two places that are the
   same change.
4. **Marks hug their content.** A block mark shrinks to fit; add `cls="fill"` only for
   full-width rows such as switches. Mark a heading's text, not a wrapper around the
   heading. Never nest marks: mark the parts.
5. **Crop to the change, and keep where you are.** A shot ends below its last mark
   (`"crop": "marks"`, the default). A change far down a long page crops between
   selectors (`{"top": "#activity-sidebar-end", "bottom": "#member-row-7"}`), and a cut
   edge fades. The browser frame shows the page's real URL.
6. **One cast.** Coast Range SAR (CRSAR; legal name Coast Range Search and Rescue Society),
   team admin Alex Chen, member Cameron Ruiz, and the cast in
   [Web.MockupSeed](../test/support/mockup_seed.ex). A second team is Valley SAR (VSAR).
   Phone numbers are 604-555-01xx; SAR Duty's own number is 604-555-0100. Never a real
   person, team, or number: issues are public.
7. **Desktop first, phones for phone tasks.** Desktop at 1280 (1024 for a narrow settings
   page), phones at 390 in an iPhone frame.
8. **Words follow [writing.md](writing.md).** Mock copy is proposed copy: glossary words,
   short sentences, values as `Service.Format` writes them.
9. **Light mode, 2x, JPG in issues.** Screenshots are attached to the issue, never
   committed.

## A round

A round lives in `tmp/mockups/<topic>/`, which git ignores. Start from the example, which
adds a switch to Account settings:

```sh
mkdir -p tmp/mockups && cp -R tools/mockups/example tmp/mockups/<topic>
tools/mockups/app-css.sh                                  # today's CSS and fonts
tools/mockups/dump.sh tmp/mockups/<topic>/dump_test.exs   # real/*.html
python3 -I tmp/mockups/<topic>/build.py                   # the mockup pages
node tools/mockups/shots.mjs tmp/mockups/<topic>          # shots/*.png and .jpg
python3 -I tools/mockups/review.py tmp/mockups/<topic> > tmp/mockups/<topic>/review.html
```

The first time, install Puppeteer into `tmp/`; `shots.mjs` drives the Chrome in
`/Applications`:

```sh
npm install --prefix tmp/puppeteer puppeteer-core@24
```

A round's files:

| File            | What                                                                         |
| --------------- | ---------------------------------------------------------------------------- |
| `dump_test.exs` | Seeds the cast, adds what the topic needs with the app's fixtures, dumps it. |
| `build.py`      | Splices the proposal into `real/` pages and writes one page per shot.        |
| `shots.json`    | Each shot's `page`, `title`, `lead`, `pins`, and its frame and crop.         |
| `intro.html`    | The review page's Overview tab: verdict, what changed, open questions.       |

`dump_test.exs` calls `MockupSeed.team()` and ends with `MockupSeed.dump/1`, which writes
to `real/`. `dump.sh` copies the test into `test/mockups/` for the run only. Times the
seed makes change every run, so splice around them with `cut(s, start, end, new)`, not
`sub` on the exact text.

A `shots.json` entry may also set `frame` (`browser`, the default; `phone`; or `none` for
a page that draws its own frames, such as `sms()` or `mail()`), `url`, `width`, `crop`
(`marks`, `full`, or `{top, bottom}` selectors), and `pad`.

## The kit

| File                                  | What                                                                   |
| ------------------------------------- | ---------------------------------------------------------------------- |
| [mock.py](../tools/mockups/mock.py)   | Splicing (`sub`, `cut`, `before`, `after`), marks, app pieces, frames. |
| [mock.css](../tools/mockups/mock.css) | Marks, pins, the browser and iPhone frames, Messages, mail.            |
| [mock.js](../tools/mockups/mock.js)   | What hooks would do on a live page, such as Select all's state.        |
| `shots.mjs`                           | Shoots each page in `shots.json`: 2x, cropped, framed.                 |
| `review.py`                           | The review page: an Overview tab, then a tab per shot with its pins.   |
| `dump.sh`, `app-css.sh`               | Dump a round's pages; build the app's CSS for file:// pages.           |

[Web.MockupSeedTest](../test/web/mockup_seed_test.exs) seeds the cast and dumps two
pages, so a change that breaks the kit fails in CI rather than in the next round.

## Showing and posting

Show `review.html` for review (in T3 Code, with `html_render`). Once a design is picked,
rewrite the issue body: each image followed by its pin captions as a numbered list.
Attach the JPGs with `gh issue edit <n> --body-file body.md --attach ./shots/x.jpg#alt`.
Phone shots go side by side as `<img width="320">`.

## Gotchas

- A pin at a narrow page's left edge falls off the screen: `right="inset"` pulls it
  inside, and `right=True` puts it on the right corner.
- A table clips anything outside its scroll box, so a pin on a header cell vanishes.
  `right="in"` (class `pin-in`) puts the pin inside the mark, on its right.
- The dump logs every query: `tools/mockups/dump.sh … | grep -E "Result|was not dumped"`.
- `app-css.sh` rewrites `/fonts/` to `fonts/` so file:// pages load IBM Plex.
- LiveView's reconnect toasts are dropped by `Mock.page`; a page with other hidden
  elements that show without the app's JS needs them removed in `build.py`.

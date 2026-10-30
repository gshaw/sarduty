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
   one sentence. Numbers restart on each shot, so a pin is named with its shot's label:
   B2 is pin 2 on shot B. One pin may mark two places that are the same change.
4. **Every shot has a label**, a letter set by hand in `shots.json` (`"id": "B"`). The
   kit draws it above the frame, on the review page's tab, and in the issue body, so
   anyone can say "B" and mean one picture. A label belongs to the screen, not its place:
   - Moving shots around changes no label.
   - A new shot takes the next unused letter, wherever it sits.
   - A split shot keeps its letter on the part that is still the same screen; the new
     part takes the next unused letter. Never "B2", which reads as a pin.
   - A dropped shot's letter is retired for that issue, so an old comment can't point at
     the wrong picture.
   - Pins may renumber between rounds; "round 2's B3" is precise enough.
5. **Marks hug their content.** A block mark shrinks to fit; add `cls="fill"` only for
   full-width rows such as switches. Mark a heading's text, not a wrapper around the
   heading. Never nest marks: mark the parts.
6. **Crop to the change, and keep where you are.** A shot ends below its last mark
   (`"crop": "marks"`, the default). A change far down a long page crops between
   selectors (`{"top": "#activity-sidebar-end", "bottom": "#member-row-7"}`), and a cut
   edge fades. The browser frame shows the page's real URL.
7. **One cast.** Coast Range SAR (CRSAR; legal name Coast Range Search and Rescue Society),
   team admin Alex Chen, member Cameron Ruiz, and the cast in
   [Web.MockupSeed](../test/support/mockup_seed.ex). A second team is Valley SAR (VSAR).
   Phone numbers are 604-555-01xx; SAR Duty's own number is 604-555-0100. Never a real
   person, team, or number: issues are public.
8. **Desktop first, phones for phone tasks.** Desktop at 1280 (1024 for a narrow settings
   page), phones at 390 in an iPhone frame.
9. **Words follow [writing.md](writing.md).** Mock copy is proposed copy: glossary words,
   short sentences, values as `Service.Format` writes them.
10. **Light mode, 2x, JPG in issues.** Screenshots are attached to the issue, never
    committed. A phone-width shot is `<img width="320">` in GitHub, never `![…]()`:
    GitHub draws every image as wide as the column, and a 2x phone shot runs about five
    screens tall. `body.py` writes it that way.

## A round

A round lives in `tmp/mockups/<topic>/`, which git ignores. Start from the example: a
switch on Account settings, the text on a phone, and two diagrams.

```sh
mkdir -p tmp/mockups && cp -R tools/mockups/example tmp/mockups/<topic>
tools/mockups/app-css.sh                                  # today's CSS and fonts
tools/mockups/dump.sh tmp/mockups/<topic>/dump_test.exs   # real/*.html
python3 -I tmp/mockups/<topic>/build.py                   # the mockup pages
node tools/mockups/shots.mjs tmp/mockups/<topic>          # shots/*.png and .jpg
python3 -I tools/mockups/review.py tmp/mockups/<topic> > tmp/mockups/<topic>/review.html
python3 -I tools/mockups/body.py tmp/mockups/<topic> > tmp/mockups/<topic>/body.md
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
| `shots.json`    | Each shot's `id`, `page`, `title`, `lead`, `pins`, and its frame and crop.   |
| `intro.html`    | The review page's Overview tab: verdict, what changed, open questions.       |

`dump_test.exs` calls `MockupSeed.team()` and ends with `MockupSeed.dump/1`, which writes
to `real/`. `dump.sh` copies the test into `test/mockups/` for the run only. Times the
seed makes change every run, so splice around them with `cut(s, start, end, new)`, not
`sub` on the exact text.

A `shots.json` entry may also set `frame` (`browser`, the default; `phone`; `sheet` for a
diagram; or `none` for a page that draws its own frames, such as `sms()` or `mail()`),
`url`, `width`, `crop` (`marks`, `full`, or `{top, bottom}` selectors), and `pad`. A
`frame: none` page of one phone sets `"width": 454`, so the shot is phone-width. At the
top, `"contact": true` adds `shots/contact.jpg`: every shot small, with its label, for a
round of four shots or more.

## The Overview and diagrams

The **Overview** is text: `intro.html`, with the verdict first, then what changed since
the last round, then open questions. It becomes the start of the issue body. Never make
it an image: an image can't be searched, quoted, or changed.

A **diagram** is a shot for what a page can't show:

- **A flow**, what leads to what: `flow([(title, text), …])`.
- **A timeline**, times and reminders: `timeline([(when, text), …])`.
- **A comparison**, example rows with each option's result beside today's: `table()`.
- **Data**, real counts behind a choice, such as how many templates use fields.

Wrap it in `diagram(body, lead)` and give its shot `"frame": "sheet"`: a plain card, no
browser bar, so nobody takes it for a page. Diagrams use the app's CSS and the cast's
names, times, and numbers, never empty boxes. One idea per diagram. Fuchsia stays for
marks: a diagram of a proposal is new as a whole, so it needs pins only where a caption
explains a row. It gets a label, a title, and a lead like any shot, and in the issue it
sits in the section it explains, above that section's mockups.

## The kit

| File                                  | What                                                                   |
| ------------------------------------- | ---------------------------------------------------------------------- |
| [mock.py](../tools/mockups/mock.py)   | Splicing (`sub`, `cut`, `before`, `after`), marks, app pieces, frames. |
| [mock.css](../tools/mockups/mock.css) | Marks, pins, the browser and iPhone frames, Messages, mail.            |
| [mock.js](../tools/mockups/mock.js)   | What hooks would do on a live page, such as Select all's state.        |
| `shots.mjs`                           | Shoots each page in `shots.json`: 2x, cropped, framed, labelled.       |
| `review.py`                           | The review page: an Overview tab, then a tab per shot with its pins.   |
| `body.py`                             | The issue body: each shot under its label, with its pin captions.      |
| `dump.sh`, `app-css.sh`               | Dump a round's pages; build the app's CSS for file:// pages.           |

[Web.MockupSeedTest](../test/web/mockup_seed_test.exs) seeds the cast and dumps two
pages, so a change that breaks the kit fails in CI rather than in the next round.

## Showing and posting

Show `review.html` for review (in T3 Code, with `html_render`). Once a design is picked,
rewrite the issue body: the Overview's words, then `body.md` (the contact sheet, then
each shot under its label with its pin captions). From the round's folder:

```sh
eval "gh issue edit <n> --body-file body.md $(python3 -I ../../../tools/mockups/body.py . --attach)"
gh issue view <n> --json body -q .body | python3 -I ../../../tools/mockups/body.py --attached > posted.md
gh issue edit <n> --body-file posted.md
```

`gh` swaps each `![…](./shots/x.jpg)` for its upload but leaves an `<img>` tag alone and
adds the upload to the end, so the second step moves those back into their phone shots'
tags. Check the body afterwards: every image is a `user-attachments` URL. Later edits
start from the posted body, never from `body.md`, or its `./shots/` paths break the
uploaded images. `gh pr edit` works the same way.

## Gotchas

- A pin at a narrow page's left edge falls off the screen: `right="inset"` pulls it
  inside, and `right=True` puts it on the right corner.
- A table clips anything outside its scroll box, so a pin on a header cell vanishes.
  `right="in"` (class `pin-in`) puts the pin inside the mark, on its right.
- The dump logs every query: `tools/mockups/dump.sh … | grep -E "Result|was not dumped"`.
- `app-css.sh` rewrites `/fonts/` to `fonts/` so file:// pages load IBM Plex.
- LiveView's reconnect toasts are dropped by `Mock.page`; a page with other hidden
  elements that show without the app's JS needs them removed in `build.py`.

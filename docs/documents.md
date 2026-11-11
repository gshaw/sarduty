# Documents

A document is a PDF SAR Duty prints from a text file in `priv/documents/` (#918). The
file holds what the document reads, what it says, where each part sits on the page, and
worked examples CI checks. The tax credit letter,
[tax_credit_letter.txt](../priv/documents/tax_credit_letter.txt), is the first. In code
it's `App.Document`: "template" is taken by kit templates.

A [form](#forms) is a document an organization hosts, such as EMCR's Task report (#950).
It prints for an activity, asks what SAR Duty can't know, and prints on the agency's own
page, or on one its own Typst [layout](#layout) draws.

The language is the report language's ([reports.md](reports.md)): the same lexer, the
same parser for each report and every value, and the same catalog. There is no second
parser. `App.Document` is pure: it parses, checks against the catalog, and works out
what each place holds from values it's given. It never runs a query, loads a picture,
or calls Typst: printing is App.Operation.PrintDocument's.

## The clauses

They come in this order. `report`, `const`, `ask`, `compute`, and `expect` can repeat;
`fill` comes once, and once more as `fill each` for a form's rows; `verify` comes as
`verify code` and `verify shows`, once each; the rest come once.
`layout` comes last, and every line after it is Typst.

| Clause                              | What it says                                                                                      |
| ----------------------------------- | ------------------------------------------------------------------------------------------------- |
| `document 'Tax credit letter'`      | Its name. A form starts `form 'Task report'`.                                                     |
| `about '…'`                         | One line on what it's for.                                                                        |
| `for member, year`                  | What it starts from, read as `:member` and `:year`. A form's is `for activity where …`.           |
| `report hours` and a query under it | A report, read as `hours.total`: its first row's columns. Select fields only, so each has a name. |
| `const meal = 15.00`                | A rate, read as `meal` ([Arithmetic](#arithmetic)).                                               |
| `ask injured 'Injured'`             | A question a person answers, read as `:injured` ([Forms](#forms)).                                |
| `compute` and values under it       | Values worked out, read by name ([Arithmetic](#arithmetic)).                                      |
| `title '…' by …`                    | The PDF's title and author.                                                                       |
| `lock print`                        | The PDF can only be printed (`Service.PDFLock`). Never on a form: the agency writes on it.        |
| `keep hours.primary, …`             | Values saved with the PDF: what a report reads, and answers.                                      |
| `verify code bottom right`          | Where the verify code prints, or `none` ([Verify code](#verify-code)).                            |
| `verify shows` and values under it  | What the PDF's verify page shows ([Verify code](#verify-code)).                                   |
| `needs team.signer, …`              | What publishing needs; a draft prints without ([Needs and email](#needs-and-email)).              |
| `email to member` and lines under   | The email a letter goes out with ([Needs and email](#needs-and-email)).                           |
| `page`                              | The values print on the form's own page PDF.                                                      |
| `places`                            | Where each value goes.                                                                            |
| `fill`                              | What goes in each place. `fill each people into rows` fills a row each ([Rows](#rows)).           |
| `expect with … : …`                 | A worked example: values given, and a condition that must hold.                                   |
| `layout`                            | A form's Typst layout, in place of `page` and `places` ([Layout](#layout)).                       |

A clause starts at the left edge, and the lines indented under it are its own. `--`
starts a comment.

## Values

A value is a report expression: a name, a literal, a comparison, `and`, `or`, `not`,
`is null`, `in`, `contains`, `starts with`, and `ends with`. A document adds:

- `'text {value}'` puts a value in text. `{value as format}` formats it.
- `value as format`, with Service.Format's formatters: `date_long`, `date_short`,
  `time`, `duration`, `hours`, `number`, `km`, and `money`. Dates show in the team's
  time zone.
- `value if condition` is blank when the condition is false.
- `if condition then value else value` picks one.
- `coalesce(a, b)` is the first that isn't blank, and `qr(link)` a QR code of a link.
- A form adds arithmetic and its functions ([Arithmetic](#arithmetic)).

Blank is nil or empty text: `is null` holds for it, `coalesce` skips it, and a flow
leaves it out. Text compares exactly, case and all, since an expect checks what prints.

## Names

| Name                                   | What it is                                                               |
| -------------------------------------- | ------------------------------------------------------------------------ |
| `hours.total`                          | A report's column. A record, such as a member, prints its name.          |
| `team.legal_name`, `organization.name` | The `team` and `organization` subjects' fields, with no report to write. |
| `:member`, `:year`, `:activity`        | What the document starts from.                                           |
| `:injured`                             | A form's answer.                                                         |
| `km_rate`, `total`                     | A form's const or compute.                                               |
| `today`                                | The team's date today.                                                   |
| `page`, `pages`                        | In `fill`: which copy of a form's page, and how many ([Rows](#rows)).    |
| `team.logo`, `organization.logo`       | Pictures only printing reads.                                            |
| `pdf.verify_link`                      | The published PDF's verify link, for `verify code none`.                 |

The pictures and the PDF's values print only. No report reads them, and `keep` refuses
them (#918). A signature isn't a picture: it's typed (`signature team.signer`, below).

## Places

```sql
places
  letterhead flow across, top 1in, right 1in, height 1in, gap 0.25in
  letter     flow down, top 1in, left 1in, right 1in, size 12pt, leading 14.4pt
```

A place is `text`, `image`, `flow`, or `tick`, and lengths are in `in`, `pt`, or `mm`
from the page's edges: `top` or `bottom`, and `left` or `right`. A flow stacks values in
order, down the page or across it, and leaves out the blank ones. Down, each item is
text, `space` (a blank line, or `space 4`), `image value width 3in height 0.75in pad
6pt`, which fits a picture in that box, or `signature team.signer`, a typed signature:
"/s/" and the name in Dancing Script, bold, 16pt, black, on its own line with 6 points
above and below, and a blank name drops out (#995). A letter the script lacks prints
in Arimo. Any item can end with `if condition`. Across, each item is a picture. `level with letter` puts a place's bottom edge level with a
flow's last line.

A text place's first baseline sits three quarters of its `size` below its `top`, as a
flow's does, and its text starts at its left edge. It wraps at its `width`, or between
`left` and `right`. A form adds:

```sql
places
  task_number text top 112pt, left 164pt, width 132pt, fit, size 10pt
  description text top 248pt, left 76pt, width 460pt, pitch 18pt, size 10pt
  search      tick top 170pt, left 160pt, size 9pt
  err         tick top 110pt, left 160pt, size 9pt, page 2
```

- `fit` keeps a text on one line and shrinks it until it fits its width.
- `pitch 18pt` puts its lines 18pt apart, baseline to baseline, on the page's own lines.
- `indent 233pt` starts its first line further in, after a label printed on that line.
- `lines 8`, with `pitch`, is as many of the page's lines as it has. A longer text
  shrinks, down to 6pt, until it fits them, so it never runs into the next part.
- `align right` puts each line against its right edge, as a column of money does, and
  `align center` centres it, as on a form's line. Either needs a width, or left and
  right.
- `tick` draws an X across a box `size` wide when its fill, a condition, holds.
- `page 2` puts a place on the page PDF's second page. Without it, a place is on page 1.
- `rows` repeats a row of places down the page ([Rows](#rows)).

## Verify code

Every published PDF prints its verify code on every page, since an agency may separate
them (#970): bottom left, half an inch from the edges, the QR code of its verify link,
then "Verify this document" and the link, `verify.sarduty.com/K7Q4M-2XA9H-VB3TN`. The QR
code holds the link in capitals, which fits a version 3 code. A draft prints a grey box
in its place, so a team admin can check the layout before publishing.

```sql
verify code bottom right            -- or top left, top right
verify code link only               -- or qr only, after a corner or alone
verify code none                    -- the places put qr(pdf.verify_link) and pdf.verify_link themselves
```

`verify shows` says what the verify page shows anyone holding the paper, a label and a
value a line. Without it, the page shows only the title, team, date, and state. It's
checked like `keep`: a value a report reads, an answer, or a compute, never a picture or
`pdf.verify_link`. What it printed is saved with the PDF, so the page never reads the
definition again.

```sql
verify shows
  'Task number' task.tracking_number
  'Total claimed' total as money
```

## Needs and email

`needs` names what publishing needs (#995): any value the document reads, such as a
team setting or picture, a report's value, or an answer. The letter has `needs
team.mailing_address, team.signer, team.signer_title`, and a form can wait for its
activity with `needs task.published` or `needs task.finished`, where `task` is its
report on `activities`. A blank value counts as missing, and so does a false one, which
only `needs` reads that way: `keep` and `verify shows` keep false as it is.

While one is missing, publishing refuses with the same words its page's warning banner,
Needed to publish, shows under the title: "This letter cannot be published without the
signer's title." The banner names each, with the page that fills it, or says when
the activity finishes and links its page to publish it in D4H. The check is in the
operations, `PublishTaxCreditLetter` and `PrintForm` (App.Operation.ReadDocument.needed/3),
so no page can skip it. A draft prints without them, and a form's Missing section
leaves them out. Needs attention lists a letter's blank team settings in letter season
(App.Operation.ReadDocument.settings/2 reads only those). Activities' `finished` is
true once their finish has passed, as `Activity.state/2` says; `finished_at` is always
set, so it can't stand in.

`email to member` writes the email a letter goes out with, its PDF attached: a
`subject`, and a `body` written one item a line, as a flow's, with `space` and `if`.
It's read again when the email goes, so it names the team's signer as they are then.

```sql
email to member
  subject '{:year} SRVTC {team.legal_name}'
  body
    'Attached is your {:year} tax credit letter from {team.legal_name}.'
    space
    'Questions? Contact {team.signer_email}.' if team.signer_email is not null
```

## Checks

`App.Document.check/2` checks each report with `App.Report.Compiler.select_columns/3`,
which checks a query as a report's is checked but writes no SQL. It reads the `team` and
`organization` fields a document names as a report of their own, so the catalog checks
those too. Then every name, format, place, and fill: each place filled once, a picture
only where a picture goes, a format only on a value it shows.

`App.DocumentTest` checks every file in `priv/documents/` and runs its `expect` lines.
A form's `where` is checked as a report's on
`activities`, and reads no answers: it decides whether the form shows before anyone
answers.

## Printing it

`App.Operation.ReadDocument` checks the text against the team's catalog, runs each
report with what it starts from, and adds each first row with `App.Document.put_row/5`
(records from `App.ViewData.ReportRecords.names/3`), the team's pictures, and `today`.
The caller adds the PDF's values and calls `App.Document.evaluate/3`. That gives the
title, the author, the lock, the kept values, and each place's value.

`App.Operation.PrintDocument` prints that with Typst. `App.Document.Markup` lays each
place out on letter paper, or on each page of a form's page, in as many copies as its
rows need, or puts a form's layout after a few lines that read its values. **Values reach Typst as data, never as Typst code**: they go in a
`values.json` the markup reads by key, so a name with a `*` or a `#` prints as written.
`lock print` runs `Service.PDFLock`. A QR code is an SVG from `EQRCode`, and Typst uses
no packages. `App.Operation.PrintTaxCreditLetter` does all this for a letter, and
`App.Operation.PrintForm` for a form.

## Forms

A form is a document an organization hosts for its teams (#950), such as the claim a BC
team sends EMCR after an incident. Its text starts:

```sql
form 'Task report'
about 'EMCR 1.01, the task report after an incident.'
for activity where kind = 'incident'
```

- **`where`** says which activities show it, as a report's `where` on `activities`.
  `App.Document.shown_on/1` is the query that finds `:activity` when the form shows on
  it, and `PrintForm` refuses any other activity.
- **`ask name 'Label'`** is a question, read as `:name`. `default` is the answer until
  someone gives one, and can read an answer above it: `default :meals_provided`.
  `choose 'Yes', 'No'` lists the answers, `hint '…'` goes under the label, and
  `remember` starts from the team's last answer, which the caller gives. An answer is
  text, a number, or a date, by its default. `App.Document.answers/2` reads what a person
  typed and says what's wrong with it.
- **`page`** prints the values on the form's own page PDF: every page of it, each at its
  own size, any paper. Typst draws a PDF's page but can't count them, so
  `Service.PDFPages` reads the page tree's `/Count`. A form's places say which page
  they're on.

Values print in black Arimo, as a form typed in Acrobat. A form is never locked.

### Preparing a form

A form's places come from its page, measured on a Mac with
[tools/forms/find_places.py](../tools/forms/find_places.py). Each place's comment names
the printed label it sits after, and the script finds it and writes the place's lengths,
leaving its other options as they are:

```sql
places
  task_number text top 91.3pt, left 156.7pt, width 105.7pt, fit, size 10pt  -- after 'Task Number:'
  others_hours text top 281.8pt, left 475.6pt, width 39.8pt, fit, size 10pt  -- after the second 'Number of Person Hours:'
  details text top 335.6pt, left 92pt, width 445.3pt, indent 232.8pt, pitch 13.6pt, lines 8, size 10pt  -- after 'Details of Task (attach additional pages if required):' lines 8
  equipment text top 488.1pt, left 92pt, width 444.3pt, pitch 14.6pt, lines 4, size 10pt  -- under 'Equipment Used/Lost' lines 4
  err_yes tick top 475.5pt, left 481.2pt, size 7.1pt  -- box after 'YES'
```

A blank is a run of underscores, as Word prints a form's lines, and a value sits 1.5pt
above it. `lines` takes the lines under the blank too, and `box after` the box after a
label. Run it, then read the diff:

```sh
uv run --with pdfplumber python -I tools/forms/find_places.py \
  priv/forms/bcsara/task_report.txt priv/forms/bcsara/task_report.pdf
```

A form can have no page at all: its own [layout](#layout) draws it each time it prints,
and it's only the text to upload. Change the layout and upload it again: saving prints
it once, and FormsTest prints it on Coast Range SAR.

A form whose agency takes a page drawn in another's layout, such as D4H's, gets a blank
page SAR Duty draws once: a Typst program beside it, such as
[supplement.typ](../priv/forms/bcsara/supplement.typ), with each line and cell at a
round number of points. Its places are written from those numbers. Draw the page again
after changing the program; `App.FormsTest` checks the PDF is the one it draws:

```sh
mise exec -- mix run --no-start tools/forms/draw_page.exs priv/forms/bcsara/supplement.typ
```

Each form's text and page are in `priv/forms/<organization>/`, as uploaded.
`App.FormsTest` saves each one as an upload does, checking it on Coast Range SAR and
running its expects, then prints it there.

- **BCSARA's Task report** ([task_report.txt](../priv/forms/bcsara/task_report.txt)) is
  EMBC's Task Report Form (#993), the page D4H draws and EMCR takes today, as Andrew's
  version 4 on production: `form 'EMBC Task Report Form'`, so an upload replaces
  production's form. It reads the incident and BCSARA's fields (Agency, Agency File #,
  ASE#, Region, Task Type, Equipment Used/Lost, Task Leader's Name) and asks nothing.
  Details of Task has 10 lines and Equipment Used/Lost 4, at 9pt. Publishing needs the
  task number, Agency, Agency File #, Region, Task Type, the description, the Task
  Leader's Name, and a finished task. The page carries two white Acrobat Sign text tags,
  for the task leader's signature and date.
- **BCSARA's Supplement** ([supplement.txt](../priv/forms/bcsara/supplement.txt)) is
  EMCR's Expense reimbursement request supplement, on a blank page in D4H's layout with
  room for 18 people, which EMCR takes today. It prints the claim's people rules: a
  row for each person who attended, by name, with their Travel km, the km rate on the
  day they started, meals, the personal equipment allowance on a response, and their
  total. It asks meals provided to everyone, and for each person On task and Meals
  provided. The header has the task number and when the task ran, and the footer the
  Task Leader's Name, Date Report Completed, and the page; the task leader signs by
  hand. More than 18 people print another copy of the page, each with its own subtotal.
  Publishing needs the task number, the Task Leader's Name, and a finished task, as the
  Expense reimbursement request's does.
- **BCSARA's Expense reimbursement request**
  ([expense_request.txt](../priv/forms/bcsara/expense_request.txt)) is EMCR's, with no
  page: its [layout](#layout) draws it in D4H's layout. The header is the team's legal
  name, mailing address, city, and postal code, then the task number and when the task
  ran. Each equipment use is a line: its km at the item's cost per km, then its hours
  (2 at least) or its uses at the item's cost per hour or per use, copied from D4H
  ([equipment.md](equipment.md#the-copy)). An item with both prints a line for each,
  the km on the first. Under the table: miscellaneous expenses (asked), the
  Supplement's subtotal as its balance forward, the subtotal, 15% for occupational
  health and safety, and the total. Its signature block (signature, date, name,
  position, email, telephone) and EMCR's own boxes are left blank, to fill by hand,
  as the Task report's and the Supplement's are (#995): the team's letter signer is the
  wrong person for a claim. It repeats
  the Supplement's people rules, reading the same answers, and a test checks the two
  agree on Coast Range SAR's claim. The bundle will drop the repeat.

### Arithmetic

A form works out what an agency's page asks for, such as EMCR's claim, from rates and
rules in its own text (#950). No rate lives in a table or in Elixir: another province's
rates are another form's consts, guarded by its expects.

```sql
const km_rate = 0.65, 0.67 from 2026-04-15
const ohs     = 15%

ask each people on_task 'On task' choose 'Yes', 'No' default 'Yes'

compute each people
  hours = hours(started_at, finished_at)
  rate  = km_rate on started_at
  total = km * rate + ...

compute
  personnel = sum(people.total)
  ohs_total = round(personnel * ohs, 2)

expect with people hours 6, km 30, started_at 2026-06-01: total = 75.10
```

- **`const`** is a value, then each value after it with the day it starts. One that
  changes is read on a day, `km_rate on started_at`, by the team's date: the last value
  that starts by then. Read alone, it's a mistake. `on`, like `as`, takes a whole value,
  so a rate gets a line of its own. Days are written `2026-04-15`, and `15%` is 0.15.
- **`compute`** works out values, a line each, read by name below it. `compute each
people` works out one for each row of report `people`: a bare name there reads the
  row's column, answer, or value first. Anywhere else only `sum(people.total)` reads it.
- **`ask each people`** asks for one answer on each row, read in the row by its bare
  name. It's kept by the row's first member or item, `row` "member:12" in
  `form_answers`, and starts from its default, which can read an answer above it, such
  as `:meals_provided`. `remember` doesn't go with it. The form page shows a row for
  each, with a box for each answer ([On an activity](#on-an-activity)).
- **Arithmetic** is `+`, `-`, `*`, and `/`, tighter than a comparison, in exact
  decimals: each number becomes a `Decimal`, so 0.67 × 30 is 20.10. A blank counts as
  0, as a spreadsheet's empty cell does; dividing by 0 is blank; a comparison with a
  blank is false. A duration is minutes, so arithmetic refuses one: `hours(duration)`
  reads it in hours.
- **Functions**: `hours(from, to)`, the hours between two times, or `hours(duration)`;
  `days(hours)`, the days they start, rounded up; `floor`; `round(x)` and `round(x,
2)`, half up; `min` and `max` of two or more; `sum(people.total)`; and `if … then …
else`. Money prints with `as money` (`Service.Format.money/1`, exact, half a cent
  up).
- **`expect`** gives a compute or a const a value, which is kept instead of worked out,
  and a report's row as its name and values: `people hours 6, km 30`, or a parent's,
  `equipment item.cost_per_hour 15`. An expect that gives one row checks it: its names
  read the row first.

The report language reads arithmetic too, so a comparison takes it, but a report
refuses it: arithmetic is a form's.

### Rows

A form can print a row for each of a report's rows, one person a row, down its page
(#950). More rows than the page holds print another copy of it:

```sql
places
  rows rows top 165.6pt, pitch 14pt, lines 18
    who   text top 3.6pt, left 44pt, width 294pt, fit, size 8.5pt
    total text top 3.6pt, left 524.6pt, width 44.4pt, fit, align right, size 8.5pt
  subtotal    text top 436.6pt, left 524.6pt, width 44.4pt, fit, align right, size 8.5pt
  page_number text top 526.85pt, left 345pt, width 225pt, fit, align center, size 9pt

fill
  subtotal = sum(rows.total) as money
  page_number = '{page} of {pages}'

fill each people into rows
  who = '{member}: {started_at as date_short}'
  total = total as money
```

- **`rows`** is where the first row starts, `pitch` from one row to the next, and how
  many `lines` a copy of the page holds. A form has one, and only on its own page. The
  places in a row are indented under it: text and ticks, each `top` from the row's
  top.
- **`fill each people into rows`** fills each row's places from one of report
  `people`'s rows, which reads its columns, answers, and values by their bare names, as
  `compute each` does. The rows keep the report's order.
- **Copies.** A copy of the page holds `lines` rows; the rest print on another copy,
  every page of the page PDF again, with every other place filled again. `page` is
  which copy it is and `pages` how many, so the form numbers them, "Page 2 of 2". With
  no rows, one copy prints. `sum(rows.total)` adds up the rows on that copy, for its own
  subtotal, while `sum(people.total)` is every row's.
- **Evaluating** gives `copies`, and each place with its `copy`. A row's places are
  named for the row, `rows.19.who`, and placed on it. An expect reads the first copy,
  and no row's places: what the rows work out, it checks with `compute each`'s values.

### Layout

A form can carry a Typst layout in place of a page (#950): `layout` comes last, alone on
its line, and every line after it is Typst, as written. Its `fill` is no place's: each
line is a value the layout reads by name, and `fill each equipment into items` a list,
a row of values for each of the report's rows. The table it draws grows with them, onto
more pages.

```sql
fill
  claimant = team.legal_name
  claim_total = total as money
  logo = team.logo

fill each equipment into items
  item = item
  total = total as money

layout
#set page(paper: "us-letter", margin: 40pt)
Claimant: #values.claimant
#for use in values.items [#use.item: #use.total \ ]
#if values.logo != none { image(values.logo, height: 30pt) }
```

- **Values reach it as data.** SAR Duty puts them in `values.json`, reads it as
  `values` above the layout's first line, and sets Arimo. A value is text, `true` or
  `false` for a condition, or `none` for a blank; a picture is the name of its file.
  It's `values`, not `v`, so the layout keeps Typst's `v()`.
- **Formats stay in the form.** A value prints as its fill formats it, `total as
money`, so the layout does no arithmetic and formats nothing.
- **An expect reads each value** by its name, as it reads a place, and no list.
- **Saving prints it** with every value blank and one blank row in each list, since
  Typst finds a mistake only when it runs. A mistake names the line of the form's
  text: `Line 140: dictionary does not contain key "claimant"`.
- **A layout has no `page` or `places`**, and its fills' names are its own: not a
  report's, a const's, or a compute's. A row holds text and conditions, no pictures.

### An organization's forms

A form belongs to an organization, in `forms` ([App.Model.Form](../lib/app/model/form.ex)),
with its page PDF's bytes in `form_pages` and its SHA-256 on the form, so a list never
loads the page. Its name and about come from its text. Its pages are under the
organization's space, `/orgs/:slug/forms` ([organizations.md](organizations.md#its-forms)).

- **A SAR Duty admin uploads it**, the text and the page, and replaces it
  (App.Operation.SaveForm). A form with a layout is its text alone. SAR Duty prepares
  each form's places on a Mac: there's no editor in the browser. Replacing raises its
  `version`, and keeps the page while the new text says `page`.
- **Saving checks it everywhere it will print**: against the catalog of each of the
  organization's teams and of Coast Range SAR, then every `expect`, then that each place
  is on a page of the page PDF (`PrintDocument.check_page/2`), or that its layout prints
  (`PrintDocument.check_layout/1`). An error names the team,
  and the upload page shows it under the file to fix. A team's RESTRICTED fields are left
  out of the check, so a form never reads one ([organizations.md](organizations.md#what-an-organization-never-sees)).
  A team without a field a form reads, such as a Records team outside BCSARA, fails the
  check, so the form can't be saved for its organization.
- **Its organization admins set it Off, Testing, or On** for every team
  (App.Operation.SetFormState, #970). Testing, team admins download draft PDFs only,
  under a Testing only banner; on, they publish. Its admins **try it** on Coast Range SAR (App.Operation.TryForm): one of its activities the
  form shows on, every answer its default, marked SAMPLE, and nothing saved.
- **Coast Range SAR has BCSARA's 27 incident fields**, with made-up values, so a BC form
  tried there fills every line. Its draft Missing hiker has no Agency File #.

### On an activity

Testing or on, a form shows in a **Forms** section above Actions on each activity its
`where` shows it on, for team admins only, never members, and never on a deleted
activity (App.ViewData.ActivityForms), each with its state: Testing, Published, Out of
date, or Not published. Its page is
`/teams/:subdomain/activities/:id/forms/:form_id` (Web.ActivityOrgFormLive), found
through the team's organization, so a form that's off or another organization's is a 404. It shows:

- **The Published section**, once one is published, the same as a letter's (#995): when
  and who, its ID linking to its verify page, Download PDF, Publish again, and Withdraw.
  No button in it is yellow. When its verify page would show something else if it were
  published today, it's out of date, and a warning banner under the title says what
  changed (`ActivityForms.changes/3`, from `PublishedPDF.changes/2`): each `verify
shows` line, or each kept value for a form with none. Page 1 folds under it, drawn from the
  saved PDF when it's opened (`/pdfs/:id/preview.png`), and History lists every PDF
  published for the activity, Replaced or Withdrawn ones too, each still downloading
  (App.ViewData.PublishedHistory). A tax credit letter's page has the same parts.

- **What SAR Duty filled in**: each column of each report, from ReadDocument's `read`.
- **Needed to publish**, a warning banner under the title while a value the form `needs`
  is missing ([Needs and email](#needs-and-email)). Publish stays on and says the same
  as an error.
- **What's missing**: each one blank that publishing doesn't need, with the page that fixes it, so the fix reaches
  D4H and every form. An activity's D4H field links to Change fields, its own details to
  Change activity, and the team's to team settings: its names to General, and its
  address, city, and postal code there too, and its signer to Signer. Fields first, questions second: an
  empty field never becomes a question. The PDF still prints with it blank.
- **The questions.** Answers save as they change (App.Operation.SaveFormAnswers), in
  `form_answers`: team, activity, name, row, the text typed, who, and when. They're the
  activity's, by name, so every form that asks the same thing starts from them, and
  they never go to D4H. A blank answer is deleted, so the default holds. An ask starts
  from the activity's answer, then for `remember` the team's last answer on any
  activity (`FormAnswer.starting/2`), then its default. `row` is "" for one answer,
  and the row's member or item for `ask each`.
- **A row for each person**, for a form that asks on each row (`ActivityForms.rows/4`):
  under a heading for its report, such as People, the Member column, a box for each of
  the row's answers, and its total, the last `compute each`, as the PDF prints it. A
  blank box shows its default in grey, such as Meals provided to everyone, and takes
  it; a choice shows its answer. Each total follows the answers as they change. A row's
  answer that's the ask's plain default, such as On task's Yes, isn't kept: a choice
  sends one for every row. A report a form only works a value out for on each row, such
  as each equipment use's total, shows too, with no boxes.
- **Publish**, on a form that's on (App.Operation.PublishDocument), opens its preview
  at `…/forms/:form_id/publish`: it checks, reads the form with the activity's answers,
  and prints once with a new ID and the verify code. The page
  shows every page as a picture (Service.PDFImages) and what publishing does: its ID,
  what its verify page shows, that its signature is left blank to sign by hand, what
  it replaces, and that it isn't sent anywhere.
  Publish there checks again and saves that same PDF in one transaction, so what's kept
  is what was looked at. When another admin published meanwhile, it says "Someone just
  published this. Reload to see it." Publish again goes through the same preview.
  History shows each publish and withdraw (App.ViewData.ChangeHistory, from the PDFs
  themselves).
- **Download draft PDF** posts the answers to Web.ActivityFormPDFController,
  since a LiveView can't send a PDF, and the browser shows it. DRAFT runs across
  each page, and the verify code's place is a grey box.
  App.Operation.CreateFormPDF keeps the answers and prints the form. A draft is never
  saved. An answer that doesn't read makes nothing.

Search finds a published PDF by its ID (`App.ViewData.Search`, Documents), and opens its
form on its activity.

## Published PDFs

A document is a draft or published, nothing in between (#970). A draft is never saved,
says DRAFT on every page, and prints a grey box where its verify code goes. Publishing
prints once with an ID and the verify code, and keeps the PDF, so a download or email
serves the same file, whatever the team's logos or the definition say now. Tax credit
letters publish when Email needs one: there's none, or it's out of date
([tax-credit-letters.md](tax-credit-letters.md)); forms on Publish
([On an activity](#on-an-activity)).

[App.Model.PublishedPDF](../lib/app/model/published_pdf.ex) is one table,
`published_pdfs`, with the bytes in `published_pdf_files`, so lists never load them.
Each row has its team, the definition's name, its subject (`member:45:2026` or
`activity:812`), its ID, title, filename, size, SHA-256, and when it was published; the
values `keep` names, its answers, and what `verify shows` printed.

- **The ID** is 15 characters from the ID card alphabet, about 74 bits, stored without
  dashes and shown 5-5-5: `K7Q4M-2XA9H-VB3TN`. Only these verify: each letter from before
  #970 got one, and its PDF printed again, once after part 1 deployed.
- **Out of date** is one rule for every published PDF (#995): its document, read today,
  would put different values on its verify page (`PublishedPDF.changes/2`). A team
  decides what counts by what it puts under `verify shows`. A PDF of a document with no
  `verify shows`, such as EMCR's forms, compares the values it kept instead.
- **One current PDF** per subject and definition, held by a unique index. Publishing
  again (`publish/3`) keeps the old one, Replaced. It takes the current PDF's id the
  person saw, and refuses when another took its place meanwhile.
- **Withdraw** (App.Operation.WithdrawDocument) ends one with no new one. It stays,
  marked Withdrawn, and still downloads for team admins (`/teams/:subdomain/pdfs/:id`).
- **No delete.** A team's purge deletes them all (App.Operation.DeleteTeam).

The verify site's root takes a card code or a document ID, and the length says which:
10 characters is a card, 15 a document. A current one shows its title, team, date, and
what `verify shows` printed; a replaced or withdrawn one says so and shows nothing from
the PDF. An old letter's reference number, or its old link, is not found.

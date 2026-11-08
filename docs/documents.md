# Documents

A document is a PDF SAR Duty prints from a text file in `priv/documents/` (#918). The
file holds what the document reads, what it says, where each part sits on the page, and
worked examples CI checks. The tax credit letter,
[tax_credit_letter.txt](../priv/documents/tax_credit_letter.txt), is the first. In code
it's `App.Document`: "template" is taken by kit templates.

A [form](#forms) is a document an organization hosts, such as EMCR's Task report (#950).
It prints for an activity, asks what SAR Duty can't know, and prints on the agency's own
page.

The language is the report language's ([reports.md](reports.md)): the same lexer, the
same parser for each report and every value, and the same catalog. There is no second
parser. `App.Document` is pure: it parses, checks against the catalog, and works out
what each place holds from values it's given. It never runs a query, loads a picture,
or calls Typst: printing is App.Operation.PrintDocument's.

## The clauses

They come in this order. `report`, `ask`, and `expect` can repeat; the rest come once.

| Clause                              | What it says                                                                                      |
| ----------------------------------- | ------------------------------------------------------------------------------------------------- |
| `document 'Tax credit letter'`      | Its name. A form starts `form 'Task report'`.                                                     |
| `about '…'`                         | One line on what it's for.                                                                        |
| `for member, year`                  | What it starts from, read as `:member` and `:year`. A form's is `for activity where …`.           |
| `report hours` and a query under it | A report, read as `hours.total`: its first row's columns. Select fields only, so each has a name. |
| `ask injured 'Injured'`             | A question a person answers, read as `:injured` ([Forms](#forms)).                                |
| `title '…' by …`                    | The PDF's title and author.                                                                       |
| `lock print`                        | The PDF can only be printed (`Service.PDFLock`). Never on a form: the agency writes on it.        |
| `keep hours.primary, …`             | Values saved with the PDF: what a report reads, and answers.                                      |
| `page`                              | The values print on the form's own page PDF.                                                      |
| `places`                            | Where each value goes.                                                                            |
| `fill`                              | What goes in each place.                                                                          |
| `expect with … : …`                 | A worked example: values given, and a condition that must hold.                                   |

A clause starts at the left edge, and the lines indented under it are its own. `--`
starts a comment.

## Values

A value is a report expression: a name, a literal, a comparison, `and`, `or`, `not`,
`is null`, `in`, `contains`, `starts with`, and `ends with`. A document adds:

- `'text {value}'` puts a value in text. `{value as format}` formats it.
- `value as format`, with Service.Format's formatters: `date_long`, `date_short`,
  `time`, `duration`, `hours`, `number`, and `km`. Dates show in the team's time zone.
- `value if condition` is blank when the condition is false.
- `if condition then value else value` picks one.
- `coalesce(a, b)` is the first that isn't blank, and `qr(link)` a QR code of a link.

Blank is nil or empty text: `is null` holds for it, `coalesce` skips it, and a flow
leaves it out. Text compares exactly, case and all, since an expect checks what prints.

## Names

| Name                                               | What it is                                                               |
| -------------------------------------------------- | ------------------------------------------------------------------------ |
| `hours.total`                                      | A report's column. A record, such as a member, prints its name.          |
| `team.legal_name`, `organization.name`             | The `team` and `organization` subjects' fields, with no report to write. |
| `:member`, `:year`, `:activity`                    | What the document starts from.                                           |
| `:injured`                                         | A form's answer.                                                         |
| `today`                                            | The team's date today.                                                   |
| `team.logo`, `organization.logo`, `team.signature` | Pictures only printing reads.                                            |
| `pdf.reference`, `pdf.verify_link`                 | The PDF's reference number and verify link.                              |

The pictures and the PDF's values print only. No report reads them, and `keep` refuses
them, so the signature never reaches a report (#918).

## Places

```sql
places
  letterhead flow across, top 1in, right 1in, height 1in, gap 0.25in
  letter     flow down, top 1in, left 1in, right 1in, size 12pt, leading 14.4pt
  verify     image right 1in, width 1in, height 1in, level with letter
```

A place is `text`, `image`, `flow`, or `tick`, and lengths are in `in`, `pt`, or `mm`
from the page's edges: `top` or `bottom`, and `left` or `right`. A flow stacks values in
order, down the page or across it, and leaves out the blank ones. Down, each item is
text, `space` (a blank line, or `space 4`), or `image value width 3in height 0.75in pad
6pt`, which fits a picture in that box. Any item can end with `if condition`. Across,
each item is a picture. `level with letter` puts a place's bottom edge level with a
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
- `tick` draws an X across a box `size` wide when its fill, a condition, holds.
- `page 2` puts a place on the page PDF's second page. Without it, a place is on page 1.

## Checks

`App.Document.check/2` checks each report with `App.Report.Compiler.select_columns/3`,
which checks a query as a report's is checked but writes no SQL. It reads the `team` and
`organization` fields a document names as a report of their own, so the catalog checks
those too. Then every name, format, place, and fill: each place filled once, a picture
only where a picture goes, a format only on a value it shows.

`App.DocumentTest` checks every file in `priv/documents/` and runs its `expect` lines.
It also prints the tax credit letter's text from the same values `CreateTaxCreditLetter`
reads, and compares the two line for line. A form's `where` is checked as a report's on
`activities`, and reads no answers: it decides whether the form shows before anyone
answers.

## Printing it

`App.Operation.ReadDocument` checks the text against the team's catalog, runs each
report with what it starts from, and adds each first row with `App.Document.put_row/5`
(records from `App.ViewData.ReportRecords.names/3`), the team's pictures, and `today`.
The caller adds the PDF's values and calls `App.Document.evaluate/3`. That gives the
title, the author, the lock, the kept values, and each place's value.

`App.Operation.PrintDocument` prints that with Typst. `App.Document.Markup` lays each
place out on letter paper, or on each page of a form's page. **Values reach Typst as
data, never as Typst code**: they go in a `values.json` the markup reads by key, so a name
with a `*` or a `#` prints as written. `lock print` runs `Service.PDFLock`. A QR code is
an SVG from `EQRCode`, and Typst uses no packages.
`App.Operation.PrintTaxCreditLetter` does all this for a letter, and
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

Each form's text and page are in `priv/forms/<organization>/`, as uploaded.
`App.FormsTest` saves each one as an upload does, checking it on Coast Range SAR and
running its expects, then prints it there.

- **BCSARA's Task report** ([task_report.txt](../priv/forms/bcsara/task_report.txt)) is
  EMCR's 1.01, on EMCR's own page, unchanged. It reads the incident and BCSARA's fields
  (Agency File #, Region, Area, Task Type, people helped, Equipment Used/Lost, Task
  Leader's Name, Date Report Completed), and asks 6 things: other response personnel,
  their person hours, injured, fatalities, still missing, and whether an equipment
  repair/replacement request is attached. The task leader signs it by hand.

### An organization's forms

A form belongs to an organization, in `forms` ([App.Model.Form](../lib/app/model/form.ex)),
with its page PDF's bytes in `form_pages` and its SHA-256 on the form, so a list never
loads the page. Its name and about come from its text. Its pages are under the
organization's space, `/orgs/:slug/forms` ([organizations.md](organizations.md#its-forms)).

- **A SAR Duty admin uploads it**, the text and the page, and replaces it
  (App.Operation.SaveForm). SAR Duty prepares each form's places on a Mac: there's no
  editor in the browser. Replacing raises its `version`.
- **Saving checks it everywhere it will print**: against the catalog of each of the
  organization's teams and of Coast Range SAR, then every `expect`, then that each place
  is on a page of the page PDF (`PrintDocument.check_page/2`). An error names the team,
  and the upload page shows it under the file to fix. A team's RESTRICTED fields are left
  out of the check, so a form never reads one ([organizations.md](organizations.md#what-an-organization-never-sees)).
  A team on SAR Duty Records has no custom fields, so a form that reads BCSARA's fields
  can't be saved for an organization with one.
- **Its organization admins turn it on or off** for every team (App.Operation.SetFormEnabled),
  and **try it** on Coast Range SAR (App.Operation.TryForm): one of its activities the
  form shows on, every answer its default, marked SAMPLE, and nothing saved.
- **Coast Range SAR has BCSARA's 27 incident fields**, with made-up values, so a BC form
  tried there fills every line. Its draft Missing hiker has no Agency File #.

### On an activity

Once on, a form shows in a **Forms** section above Actions on each activity its `where`
shows it on, for team admins only, never members, and never on a deleted activity
(App.ViewData.ActivityForms). Its page is
`/teams/:subdomain/activities/:id/forms/:form_id` (Web.ActivityOrgFormLive), found
through the team's organization, so a form that's off or another organization's is a 404. It shows:

- **What SAR Duty filled in**: each column of each report, from ReadDocument's `read`.
- **What's missing**: each one blank, with the page that fixes it, so the fix reaches
  D4H and every form. An activity's D4H field links to Change fields, its own details to
  Change activity, and the team's to team settings. Fields first, questions second: an
  empty field never becomes a question. The PDF still prints with it blank.
- **The questions.** Answers save as they change (App.Operation.SaveFormAnswers), in
  `form_answers`: team, activity, name, row, the text typed, who, and when. They're the
  activity's, by name, so every form that asks the same thing starts from them, and
  they never go to D4H. A blank answer is deleted, so the default holds. An ask starts
  from the activity's answer, then for `remember` the team's last answer on any
  activity (`FormAnswer.starting/2`), then its default. `row` is "" until `ask each`.
- **Download PDF and Open PDF** post the answers to Web.ActivityFormPDFController,
  since a LiveView can't send a PDF. App.Operation.CreateFormPDF keeps the answers,
  prints the form, and saves the PDF it sends, every time (`SavedPDF.add_for_form!/5`).
  An answer that doesn't read makes nothing.

Search leaves the page out: it's found from its activity (`Web.Search.not_searched/0`).

## Saved PDFs

Every PDF a document makes is saved as it was made, so a download or email serves the
same file, whatever the team's logos or the document say now (#918, #950).
[App.Model.SavedPDF](../lib/app/model/saved_pdf.ex) is one table, `saved_pdfs`, for all
of them, with the bytes in `saved_pdf_files`, so lists never load them. Each row has its
team, title, filename, size, and when it was made, and belongs to one of:

- **A tax credit letter**: one PDF, replaced when the letter is (`put_letter!/2`).
- **An activity**, for a form: a new PDF each time one prints, none replaced
  (`add_for_form!/5`). It keeps its form and the version it printed from, who made it,
  and the values it printed that `keep` names. If the form goes, the PDF stays
  and its form is blank.

Deleting a letter deletes its PDF. A team's purge deletes them all
(App.Operation.DeleteTeam).

# Documents

A document is a PDF SAR Duty prints from a text file in `priv/documents/` (#918). The
file holds what the document reads, what it says, where each part sits on the page, and
worked examples CI checks. The tax credit letter,
[tax_credit_letter.txt](../priv/documents/tax_credit_letter.txt), is the first. In code
it's `App.Document`: "template" is taken by kit templates.

The language is the report language's ([reports.md](reports.md)): the same lexer, the
same parser for each report and every value, and the same catalog. There is no second
parser. `App.Document` is pure: it parses, checks against the catalog, and works out
what each place holds from values it's given. It never runs a query, loads a picture,
or calls Typst: printing is App.Operation.PrintDocument's.

## The clauses

They come in this order. `report` and `expect` can repeat; the rest come once.

| Clause                              | What it says                                                                                      |
| ----------------------------------- | ------------------------------------------------------------------------------------------------- |
| `document 'Tax credit letter'`      | Its name.                                                                                         |
| `about '…'`                         | One line on what it's for.                                                                        |
| `for member, year`                  | What it starts from, read as `:member` and `:year`.                                               |
| `report hours` and a query under it | A report, read as `hours.total`: its first row's columns. Select fields only, so each has a name. |
| `title '…' by …`                    | The PDF's title and author.                                                                       |
| `lock print`                        | The PDF can only be printed (`Service.PDFLock`).                                                  |
| `keep hours.primary, …`             | Values saved with the PDF. Only what a report reads.                                              |
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
| `:member`, `:year`                                 | What the document starts from.                                           |
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

A place is `text`, `image`, or `flow`, and lengths are in `in`, `pt`, or `mm` from the
page's edges. A flow stacks values in order, down the page or across it, and leaves out
the blank ones. Down, each item is text, `space` (a blank line, or `space 4`), or
`image value width 3in height 0.75in pad 6pt`, which fits a picture in that box. Any
item can end with `if condition`. Across, each item is a picture. `level with letter`
puts a place's bottom edge level with a flow's last line.

## Checks

`App.Document.check/2` checks each report with `App.Report.Compiler.select_columns/3`,
which checks a query as a report's is checked but writes no SQL. It reads the `team` and
`organization` fields a document names as a report of their own, so the catalog checks
those too. Then every name, format, place, and fill: each place filled once, a picture
only where a picture goes, a format only on a value it shows.

`App.DocumentTest` checks every file in `priv/documents/` and runs its `expect` lines.
It also prints the tax credit letter's text from the same values `CreateTaxCreditLetter`
reads, and compares the two line for line.

## Printing it

A caller runs `App.Document.queries/1` with `:member` and `:year`, adds each first row
with `App.Document.put_row/5` (records from `App.ViewData.ReportRecords.names/3`), adds
the pictures and the PDF's values, and calls `App.Document.evaluate/3`. That gives the
title, the author, the lock, the kept values, and each place's value.
`App.Operation.PrintDocument` prints that with Typst: `App.Document.Markup` lays each
place out on letter paper, every value as a Typst string so it prints as written, and
`lock print` runs `Service.PDFLock`. A QR code is an SVG from `EQRCode`, and Typst uses no
packages. `App.Operation.PrintTaxCreditLetter` does all this for a letter.

## Saved PDFs

Every PDF a document makes is saved as it was made, so a download or email serves the
same file, whatever the team's logos or the document say now (#918, #950).
[App.Model.SavedPDF](../lib/app/model/saved_pdf.ex) is one table, `saved_pdfs`, for all
of them, with the bytes in `saved_pdf_files`, so lists never load them. Each row has its
team, title, filename, size, and when it was made, and belongs to one of:

- **A tax credit letter**: one PDF, replaced when the letter is (`put_letter!/2`).
- **An activity**, for a form: a new PDF each time one prints, none replaced
  (`add_for_activity!/4`). It keeps who made it and the values it printed that `keep`
  names. The form and its version come with the forms table (#950, step 3).

Deleting a letter deletes its PDF. A team's purge deletes them all
(App.Operation.DeleteTeam).

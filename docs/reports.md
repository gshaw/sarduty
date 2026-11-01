# Reports

Reports (#768) are saved queries in a small language, run on one team's records. The
language is Google Sheets' QUERY language plus four pieces of Salesforce's SOQL: `from`,
dotted fields to a parent record, date ranges such as `LAST_N_DAYS:365`, and `:name`
values. `App.Report.run/4` is the way in.

<!-- cspell:ignore SOQL -->

```sql
select member, sum(hours)
from attendance
where status = 'Attended' and year(activity.started_at) = :year
  and member.counted = true
group by member
pivot activity.kind
order by member.name
totals
```

## How a query runs

1. `App.Report.Parser` reads the text into an `App.Report.Query`. It knows no fields.
2. `App.Report.Compiler` checks every name against `App.Report.Catalog` before anything
   runs, and writes SQL. A mistake names its line and the closest field.
3. `App.Report.Runner` runs the SQL, reads the rows back by type, and makes the pivot's
   columns and the total row in Elixir.

The SQL reads each subject's `source`, an Ecto query already scoped to the team, as a
subquery, and joins the sources of the parents the query names. Names in the SQL come
only from the catalog; every value a query writes is a parameter. A query never reaches
a table the catalog doesn't name, so there is no `team_id` for it to forget.

## The catalog is an allowlist

Like the MCP tools, the fields leave out contact details, addresses, coordinates, letter
text, and keys. `select email from members` answers "Reports leave out contact details."

**A field is a rule's existing home, never a copy.** `status` is
`Attendance.status_word_dynamic/1`, `standing` is `Standing.dynamic/1`, `counted` is
`Member.counted_dynamic/0`, `hours_tag_count` is `Activity.hours_tag_count_dynamic/1`,
and `not_seen(days)` is `Member.not_seen_query/4`. A rule that has only a pure function
gets an SQL twin on its model, with a test that the two agree, before a field reads it.

Adding a field:

1. Select its column in the subject's `source`, from the rule's home.
2. Add a `%Field{}` with a label and a type. `App.ReportTest` fails on a field without
   them, and runs every subject with every field.
3. A field that holds one of a few values is a `:choice` with the glossary's words as
   labels (docs/writing.md): a query compares by the label or the value, and a cell shows
   the label.

## Dates and time zones

SQLite has no time zones. `App.Report.LocalTime` writes a stored UTC time as the team's
local time with a CASE over the zone's periods from tzdata, so `year()`, `month()`, and
`days_since()` follow daylight saving time. Ranges (`TODAY`, `THIS_YEAR`,
`LAST_N_DAYS:n`) and `date '2026-01-01'` become UTC bounds in `App.Report.Range`.

## Limits

5,000 rows, 12 pivot columns, and 2 seconds. A run past 2 seconds is interrupted (the
connection's timeout interrupts SQLite) and says to narrow the report.

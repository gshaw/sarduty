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

A source selects only the columns the query reads. When a column needs a join of its
own, such as `attended_count` adding up the team's attendance, the source is an
`App.Report.Source` that says which columns need which join, and the join comes only with
them (#784). Before this, every page added up every activity's attendance for each of
its nine queries, and Activities took 274 ms where the old page took 10.

## The catalog is an allowlist

Like the MCP tools, the fields leave out contact details, addresses, coordinates, letter
text, and keys. `select email from members` answers "Reports leave out contact details."

**A field is a rule's existing home, never a copy.** `status` is
`Attendance.status_word_dynamic/1`, `standing` is `Standing.dynamic/1`, `counted` is
`Member.counted_dynamic/0`, `hours_tag_count` is `Activity.hours_tag_count_dynamic/1`,
and `not_seen(days)` is `Member.not_seen_query/4`. A rule that has only a pure function
gets an SQL twin on its model, with a test that the two agree, before a field reads it.

A field with a `query` is a rule's own query of ids (#784): it's true for the rows the
rule keeps, `id IN (that query)`, so a rule that's already a query needs no twin.
`current` is `Activity.overlapping/3` over Current, `recent` is
`Activity.finished_recently/3`, and `on_team(period)` is `Member.on_team_query/4`. A
field's arguments are a number of days, a period (`'all'`, a year, or `'90d'`), a tag's
title, or a group's title; a period, a tag, or a group can be a picked value, as in
`activity_count(:when, :tag)`, and its menu lists All, then the choices. A picked group
is its id, as Members' Group filter has always linked (`in_group(:group)`).

Adding a field:

1. Select its column in the subject's `source`, from the rule's home. A column that
   reads a join names it in the source's `needs`.
2. Add a `%Field{}` with a label and a type. `App.ReportTest` fails on a field without
   them, and runs every field alone, which fails on a join missing from `needs`.
3. A field that holds one of a few values is a `:choice` with the glossary's words as
   labels (docs/writing.md): a query compares by the label or the value, and a cell shows
   the label.

## The page's clauses

Clauses after the query draw the page around its rows (#784): a search box, tiles with
counts, filter menus, sortable headers, and pages. `App.Report.page/4` runs a report
this way; `App.Report.run/4` keeps every row the picks keep, for Download CSV.

```sql
select title, started_at, attended_count
from activities
order by started_at desc
search title, ref_id, tags
switch activity 'Kind'
  option incident 'Incidents' where kind = 'incident'
  option exercise 'Exercises' where kind = 'exercise'
filter when 'When'
  option past 'Past' where started_at <= NOW
  option future 'Future' where started_at >= NOW sort date
  each year(started_at) where year(started_at) = :when
filter status 'Status' more
  option draft 'Draft' where published = false
sort date 'Date' started_at
page 50
```

- `search` ORs `contains :q` over its fields. A list field matches on any of its titles.
- `switch` is the tiles, All first. Each counts its rows with every other pick on and the
  search off, all in one query; a query that groups counts each tile's groups on its own.
- `filter` is a menu, All first. `required` drops All, `default` picks where it starts (a
  value, or `THIS_YEAR`), and `more` puts it behind More filters. A filter with neither
  options nor `each` shows the menu of the value its name gives a field: `filter when
'Period'` with `on_team(:when)` lists All, the last 30 to 365 days, and the years.
- `option` is a value for the URL, a label, the `where` it adds, and the sort it picks,
  if any. `each` makes an option for each value of a field: each year, a choice's
  values, or a list's titles.
- `sort` is a column header: its label, or its first field, names the column. `date` in
  the URL sorts as written, `date-` the other way.
- `page` shows that many rows at a time, and sorts by `id` last so no row lands on two.

A pick is a `:name` value, like `:year`, and rides in the URL by name, so the `reports`
table keeps no more than it did. A pick can name several options, as the attendance
check's link to Members does with `standing=active,away`: their `where`s are ORed, and
the menu says "Active or away". A switch's pick with no tile shows as a menu in the bar.
A value no menu has starts the control where it starts, its default or All. `App.Report.Picks` turns the picks into a plain query,
so the catalog checks every name and the limits hold. Before anything runs, every
option, each, search, and sort is checked as the query's own is, and a mistake names its
part: `Line 5, option draft: activities has no field publshed.` A filter whose value the
query reads, as in `where year(started_at) = :year`, must be `required`. A report with
`pivot` has no tiles, pages, or sorts.

<!-- cspell:ignore publshed -->

`<.report_page>` draws them on a report's page and in the editor's preview, from the
same `App.Report.View`. On the page, each pick is a link or a menu that patches the URL,
and the URL leaves out what a control starts on; a team's own report starts on the picks
saved with it. In the editor, a tile, a menu, or a header changes the preview, and Save
keeps the picks as the report's values.

## Lists drawn by a report

Activities is drawn by its report (#784): `App.Report.Lists` holds the list's text, and
the page runs it with `App.Report.page/4`. The tiles, the search, the filters, the sorts,
and the pages come from the clauses; the cells, Add activity, and Save as report stay in
the page's code, which passes its own table to `<.report_page>`. A filter's name is the
URL param the page always used, so Home's links still open the same list.

Save as report opens New report on the list's text, with the picks as its values and in
its name: `/reports/new?list=activities&activity=exercise`. A copy draws plain report
cells, not the list's own. Lists are not on the Reports page.

A field can say which teams, and which viewers, may read it (`shown` in
`App.Report.Field`). To one that may not, it's no field, and an option, sort, or search
that reads it drops out of the page, as Records teams have no Required fields filter. A
choice can hide some of its values from a viewer too (`hidden_choices`), and an option
that compares with one drops out. The text has no rule of its own for who sees what.

A page runs as a team admin unless it's given `team_admin?: false`, for a member
(decision 4 of #784). A member can't read Details missing, Not seen, Holds
items, or D4H access, so those filters go. Their `standing` is `Standing.visible/2`'s:
someone away is Active, so they get the Active tile, and its count can't give away who
is away. Reports themselves are only for team admins.

`App.Report.ids/4` gives the ids of every row the picks keep without reading the
fields the list shows, so a count elsewhere can agree with the list it links to.

## Dates and time zones

SQLite has no time zones. `App.Report.LocalTime` writes a stored UTC time as the team's
local time with a CASE over the zone's periods from tzdata, so `year()`, `month()`, and
`days_since()` follow daylight saving time. Ranges (`TODAY`, `THIS_YEAR`,
`LAST_N_DAYS:n`) and `date '2026-01-01'` become UTC bounds in `App.Report.Range`.

A year compared with one, as in `year(started_at) = :when`, is a range too: the stored
time between two UTC bounds, not each row's local year worked out first. It keeps the
same rows and reads 3,559 activities in a quarter of the time (#784).

`LAST_N_DAYS:n` is today and the n days before it, whole days in the team's time zone:
`Service.DayRange.last/3`, the app's one rule for "the last n days" (#784). Activities'
Last 30 days, Members' Period, and the attendance check mean the same.

## Built-in and saved reports

Built-in reports live in `App.Report.BuiltIn`, change with the app, and can be copied
but not changed; a test opens every one. A team's own reports are rows in `reports`
(`App.Model.SavedReport`): the query and its picked values, never the rows. The query
is checked again on every run, so a field that goes fails with a message on the
report's page. `App.ViewData.Reports` treats both the same, by `id` in the URL: a team's
own report by its row's id, a number, and a built-in one by its slug, never a number.

## Limits

5,000 rows, 12 pivot columns, and 2 seconds. A page shows at most 500 rows, and a report
with `page` has no 5,000-row limit, since each page reads only its own. A run past 2 seconds is interrupted (the
connection's timeout interrupts SQLite) and says to narrow the report.

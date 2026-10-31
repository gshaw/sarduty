# List views experiment (#768)

An experiment, not for merge. It asks whether a report can describe its list page (the
search, the stat switch, the filters, the sorts, and the pages) so that the app's lists
could run on the report engine.

`specs/*.report` are ten list pages written in the proposed clauses. `list_spec.ex`
parses those clauses and turns each pick into a plain report that `App.Report.run/4`
runs. It runs no SQL of its own. Each script runs the page's own code and the spec on
the same picks, and compares the rows, the tile counts, and the order of the first two
pages.

```sh
mkdir /tmp/lv && sqlite3 db/sarduty_dev.db ".backup /tmp/lv/dev.db"
export LIST_VIEWS_DB=/tmp/lv/dev.db
mise exec -- mix run --no-start tools/list-views-experiment/activities.exs
```

Run on 2026-10-31 against a copy of the sanitized dev database (7 teams), 1,763 of
1,763 checks matched:

| List                                                 | Checks |
| ---------------------------------------------------- | ------ |
| Activities                                           | 245    |
| Members                                              | 354    |
| A member's Attendance tab                            | 321    |
| Qualifications, Expiring, one qualification's awards | 179    |
| Equipment                                            | 90     |
| Groups                                               | 56     |
| Tax credit letters                                   | 308    |
| Milestones                                           | 210    |

What the language needed is in the commit "Experiment: list views on the report
language", each part marked `Experiment (list views)`.

# Production access

People and agents reach production one way: [bin/prod](../bin/prod). It runs a task from
[lib/app/ops/](../lib/app/ops) inside the running app, and the app records each run as a
`prod_task` event on `/admin/events`: who ran it, the agent if one did, the task, its
arguments, why, the rows, and the outcome. It's kept two years and backed up with the
database. The output is never kept, since it can name members, and nothing goes into
GitHub. The design and its reasons are #517.

```sh
bin/prod list                                       # the tasks, one line each
bin/prod query "select count(*) from teams" --why "#970 who signs"
bin/prod jobs RenewLetterCodes --minutes 15 --why "#970 backfill after v491"
bin/prod fix make-admin someone@example.org --why "new admin"
bin/prod backup --why "dev copy for #584"
bin/prod console --why "app won't boot"
```

- **`--why` is required**: an issue number or a sentence. It's what makes the record
  readable later.
- **Who you are** is the SAR Duty admin with your `git config sarduty.email`, or
  `user.email` when that isn't set. It's self-declared, as with any shell. The ssh token
  is the boundary, and each app has its own, expiring
  ([deployment.md](deployment.md#deploying)).
- **Reads run any time a question needs production.** A task that changes data runs as
  `bin/prod fix TASK`, and only when asked.
- **Transport:** `fly ssh` with `FLY_SARDUTY_SSH_TOKEN`, which `bin/prod` reads from
  fnox, then `bin/sarduty rpc` calls `App.Ops.main/1` with the request as base64 JSON.
  `bin/prod` prints only what's between `App.Ops`'s markers, and exits 1 when the task
  failed and 3 when the app didn't answer.

## query

`query` runs one SQL statement on its own read-only connection, so a write fails however
it's written. It stops at 10 s and prints at most 50 rows. A heavy query competes with
every page and the D4H sync on one shared CPU, and on 2026-10-25 one ran the machine
throttled for 7 minutes. Aggregate in SQL and return a few rows. Analysis that needs
every row runs on a sanitized copy ([deployment.md](deployment.md#database-and-backups)).

A query's SQL is kept in its event. Find rows by id, not by a person's name or email,
where you can.

## Adding a task

A question asked twice, or any write, becomes a task: a module in `lib/app/ops/` that
does `use App.Ops.Task` and defines `run/1`, plus a line in `App.Ops`'s list. It's
reviewed in its PR like any code, before it ever runs.

- A task never reads or prints a secret.
- It prints the fewest fields that answer the question.
- A task that changes data says `write: true`, so it runs only through `bin/prod fix`.
- A one-off fix is a task deleted after it ran; git keeps it.

## backup and console

`backup` has the app write a consistent copy of the database (`App.Ops.Backup`), then
`bin/prod` tars it with the team logos over `fly ssh`, encrypts it to
`BACKUP_AGE_RECIPIENT`, and saves it in `backups/`. No plain copy lands on disk.

`console` records that a shell opened, then opens one on the machine. It's for people,
when no task does the job: rolling back a migration, reading `repo_slow.log`, or letting
an admin back in when D4H drops both admins. It opens even when the app doesn't answer,
since that's when it's needed. What's done in the shell isn't recorded, so say it on the
issue. Anything done there twice becomes a task.

## The hook

[.claude/hooks/prod-guard](../.claude/hooks/prod-guard) runs before every Bash command an
agent runs in this repo. It refuses `fly ssh`, `fly console`, `fly machine exec`,
reading `FLY_SARDUTY_SSH_TOKEN`, and `bin/prod console`. It asks you before `bin/prod fix`
and `bin/prod backup`. It checks the command's text, so it stops habits, not a
determined person. The token is the boundary.

Records gets the same shape in its own repo.

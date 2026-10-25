# Background jobs

Oban runs jobs from the app's own SQLite database (`Oban.Engines.Lite`, set up in
`config/config.exs`). A job retries by itself, so it suits work nobody waits on. Work a
person needs the answer to stays inline. The workers are in
[lib/app/worker/](../lib/app/worker).

## Job or inline

Make it a job when nobody waits for the answer (notices, reminders, pass pushes), when
a retry would fix a failure, when it fans out to many people, or when it runs later or
on a clock.

Keep it inline when the person needs the answer to go on: a key check, a confirm text,
a download. Also keep it inline when it writes to D4H. A retried POST can add a row
twice, so change sets stay inline: each row records D4H's answer, and the person sends
again ([change-sets.md](change-sets.md)). A slow result for this page only goes in
`start_async` or `assign_async`, as the mileage report does, not in a job.

## How a job is shaped

- **Args are ids and plain values**, like `%{reminder_id: 42}`. Never a struct, a code,
  a token, or personal data: job rows stay a week, and they are in the replica and
  every backup. An email address is fine only when no row holds it, as for a login code.
- **Safe to run twice.** A deploy can kill a job that Lifeline later reruns, and a retry
  can follow a call that worked but timed out. Check a status or a fingerprint before
  acting. A rare second email is fine; a second D4H row or letter is not.
- **Inserted in the same transaction as its row**, so there is never a row without its
  job, or a job that runs before its row exists.
- **Inserted through the worker's `enqueue`**, which takes structs and builds the args,
  like `SyncTeamChangesWorker.enqueue/1`. Operations call it; a LiveView calls it only
  when there is nothing else to do, like a refresh button.
- **Unique when a second copy repeats the work**: per team for refresh, sync, and pass
  pushes. Give `period: :infinity`, since Oban's default only looks back 60 seconds.
- **Retries match how long the result is useful.** Oban's default, 20 attempts over
  weeks, fits nothing here. A login code gets 3 within a minute. A job whose retry could
  do harm, or whose next run is the retry, like the sync, gets 1.

## Failures

Return `{:error, reason}` or raise when a retry may fix it. `App.Worker.ErrorReporter`
sends the last attempt to Honeybadger. Return `{:cancel, reason}` when only a person
can fix it: a rejected key, no email, a record gone. Never return `:ok` for a send that
failed.

Honeybadger is for us. A failure the team needs to see also goes on a row the page
shows, like `ChangeSetRow.status`. A job with one attempt that a deploy kills is
discarded without a word, so a job that matters gets 2 or more, or a status.

## Queues

| Queue     | Limit | For                                                        |
| --------- | ----- | ---------------------------------------------------------- |
| `default` | 5     | Small jobs someone may be waiting on: login codes, notices |
| `refresh` | 1     | The full D4H refresh, nightly or from a button             |
| `sync`    | 1     | The 10-minute D4H sync                                     |

`refresh` and `sync` take 1 so two teams' copies never hold the write lock together.
Add a queue only when a job needs a new limit.

## Why

- **SQLite has one writer.** A job costs three short writes. What hurts is a long
  transaction, so never wrap one around an HTTP call.
- **A deploy gives running jobs 15 seconds** (`kill_timeout = 20` in `fly.toml`). A job
  still running is put back by Lifeline an hour later, or discarded if it was the last
  attempt.
- **A click that takes over 30 seconds reloads the page**, and its flash is lost. Work
  that long is a job or `start_async`.
- **In tests a job runs as it is inserted** (`testing: :inline`), once, and inside the
  caller's transaction rather than after the commit. Use
  `Oban.Testing.with_testing_mode(:manual, …)` and `assert_enqueued` to test that a
  job was queued, and call `perform/1` with `attempt:` set to test the last attempt.

# Deployment

One Fly app, `sarduty`, in `yyz`: one always-on machine with a volume at `/mnt/sarduty`
holding the SQLite database and team logos. Deploys are manual.

It answers on two hosts, each with a Fly certificate (`fly certs list`): `sarduty.com`,
and `verify.sarduty.com` for checking ID cards. The verify host is a Cloudflare CNAME to
`sarduty.com`, DNS only: proxying would stop Fly issuing its certificate. Cloudflare warns
that this exposes the origin IP; it's Fly's shared edge, already public through
sarduty.com.

## Deploying

```sh
fly deploy
```

From `main`, after CI is green. The [Dockerfile](../Dockerfile) builds a release;
[rel/overlays/bin/server](../rel/overlays/bin/server) starts it.

Each app has its own Fly tokens in fnox, so a script or an agent never needs the full
login: `FLY_ACCESS_TOKEN=$(fnox get FLY_SARDUTY_DEPLOY_TOKEN) fly deploy`, and
`FLY_SARDUTY_SSH_TOKEN` for `fly ssh`, which is all it can do. They expire 2027-04-22;
make new ones with `fly tokens create deploy -a sarduty -x 4320h` (or `ssh`). Who reaches
production, and how, is #517.

**Nothing in the build downloads through GitHub's release redirect with Erlang's
`:httpc`.** Since OTP 29 it refuses that redirect's 10 KB of headers, so a build that
compiles dependencies from scratch failed (#497). exqlite builds from the SQLite source
it ships, vix builds against Debian's libvips, and mdex downloads from its own Cloudflare
mirror (`config/config.exs`). A new dependency that downloads a precompiled binary needs
the same check: `fly deploy --build-only` after a change to `mix.lock` or
`config/config.exs` rebuilds everything.

**Migrations run at boot**, not as a release command: `App.Application.start/2` calls
`App.Release.migrate/0` before anything else. It starts its own 2-connection Repo; the
`Ecto.Migrator` child Phoenix generates for SQLite runs on the app's 5 and failed on a
fresh database, since SQLite prepares an ALTER TABLE against the connection's cached
schema. A migration that fails keeps the app from starting, so test migrations against a
copy of production data when they touch existing rows.

For a PR with a migration:

- Prefer additive changes: a new table, or a nullable column. The previous release ignores
  what it doesn't know, so going back to it needs no down migration.
- Run it up, down, and up again on a copy of the data (`sqlite3 <db> ".backup <copy>"`),
  and load the changed schema through Ecto after each up.
- To go back, deploy the previous release first. Roll the migration back afterwards, and
  only if you have to, with `App.Release.rollback(App.Repo, <previous version>)` through
  `bin/sarduty eval`. The other order leaves the new code reading a column that is gone.

## Database and backups

- **Litestream** replicates the database continuously to Cloudflare R2
  ([litestream.yml](../litestream.yml)). `bin/server` restores from the replica when the
  database file is missing, then runs `litestream replicate` in the background.
  `App.Repo` waits up to 30 s for SQLite's write lock. Litestream's metrics, such as
  `litestream_sync_seconds`, are in Fly's metrics; a sync that takes 1 s is Litestream
  waiting for the lock. The lock errors of #416 were exqlite's: before 0.42, a connection
  waiting for the lock froze any process that freed one of its statements, including
  the holder, and on our one CPU that froze the whole VM until the wait ran out.
- **Slow holds**: `App.Repo.SlowLog` names whatever holds the write lock over 5 s, while
  it holds it: the transaction's process and what it is running, and which OS process
  holds the lock (this app, Litestream, or another). It also reports statements over
  5 s, lock errors, and a stalled VM. Reports go to `/mnt/sarduty/repo_slow.log` first
  (`fly ssh console -C "tail -50 /mnt/sarduty/repo_slow.log"`), then to the log and a
  `repo.slow` event in Honeybadger Insights, which drops events during a lock burst. It
  stays after #416: a 5 s hold is worth knowing about.
- **Snapshots** by hand: [backups/backup.sh](../backups/backup.sh) has the app write a
  consistent copy with `VACUUM INTO`, then tars it and the logos over `fly ssh` into
  `backups/` (gitignored), encrypted with age and stamped to the minute.
- **A dev copy** from a snapshot: `AGE_IDENTITY=<identity file> mise run sanitize
backups/<snapshot>` writes `db/sarduty_dev.db` with every name, email, phone, address,
  incident, and credential replaced by stable fakes. Admins and their member rows stay
  real. It refuses to write if a real value is left anywhere
  ([backups/sanitize.exs](../backups/sanitize.exs)).

## Changing production data

Only when asked. Every change goes through `bin/sarduty eval` on the machine:

```sh
fly status --app sarduty    # note the machine id
fly ssh console -a sarduty --machine <ID> -C 'bin/sarduty eval "<code>"'
```

- Start the code with `Application.ensure_all_started(:sarduty);` or it fails with
  "could not lookup Ecto repo".
- Outer quotes are `"`, inner quotes are `\"`, statements are separated by `;`, and
  `IO.inspect` shows results. Use bang functions so a miss raises.
- `import Ecto.Query;` before using `from`.
- "app has no started VMs" means `fly machines start <ID>`.

For example, making a user an admin:

```sh
fly ssh console -a sarduty --machine <ID> -C 'bin/sarduty eval "Application.ensure_all_started(:sarduty); user = App.Repo.get_by!(App.Accounts.User, email: \"user@example.com\"); App.Repo.update!(Ecto.Changeset.change(user, is_admin: true)); IO.puts(\"ok\")"'
```

Read the row first, then change it, and say what changed on the issue or PR.

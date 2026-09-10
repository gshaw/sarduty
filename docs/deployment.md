# Deployment

One Fly app, `sarduty`, in `yyz`: one always-on machine with a volume at `/mnt/sarduty`
holding the SQLite database and team logos. Deploys are manual.

## Deploying

```sh
fly deploy
```

From `main`, after CI is green. The [Dockerfile](../Dockerfile) builds a release;
[rel/overlays/bin/server](../rel/overlays/bin/server) starts it.

**Migrations run at boot**, not as a release command: `App.Application.start/2` calls
`App.Release.migrate/0` before anything else. A migration that fails keeps the app from
starting, so test migrations against a copy of production data when they touch existing
rows.

## Database and backups

- **Litestream** replicates the database continuously to Tigris
  ([litestream.yml](../litestream.yml)). `bin/server` restores from the replica when the
  database file is missing, then runs `litestream replicate` in the background.
- **Volume snapshots** by hand: [backups/backup.sh](../backups/backup.sh) tars the whole
  volume over `fly ssh`, logos included, into `backups/` (gitignored).

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

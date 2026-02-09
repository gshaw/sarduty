---
name: Production Database Changes on Fly.io
description: Query or modify production database records on Fly.io using SSH console and Ecto.
---

## Scope

Use this skill when you need to inspect or modify production database records on the Fly.io deployment.

## Prerequisites

- Fly CLI installed and authenticated
- App is deployed and running (`fly status --app sarduty`)
- Know the app name (from `fly.toml`: `sarduty`)

## Checklist

### 1. Get the Machine ID

```bash
fly status --app sarduty
```

Note the machine ID (e.g., `87ede0c01595e8`). If only one machine exists, you can omit `--machine` flag.

### 2. Run Database Queries via SSH Console

Use `fly ssh console` with the `eval` command:

```bash
fly ssh console -a sarduty --machine <MACHINE_ID> -C 'bin/sarduty eval "<ELIXIR_CODE>"'
```

**Critical:** Always include `Application.ensure_all_started(:sarduty)` at the beginning of eval code.

### 3. Common Patterns

**Query by email:**
```bash
fly ssh console -a sarduty --machine <MACHINE_ID> -C 'bin/sarduty eval "Application.ensure_all_started(:sarduty); user = App.Repo.get_by(App.Accounts.User, email: \"user@example.com\"); IO.inspect(user)"'
```

**Update a field:**
```bash
fly ssh console -a sarduty --machine <MACHINE_ID> -C 'bin/sarduty eval "Application.ensure_all_started(:sarduty); user = App.Repo.get_by!(App.Accounts.User, email: \"user@example.com\"); changeset = Ecto.Changeset.change(user, is_admin: true); App.Repo.update!(changeset); IO.puts(\"Updated\")"'
```

**Query with Ecto.Query:**
```bash
fly ssh console -a sarduty --machine <MACHINE_ID> -C 'bin/sarduty eval "Application.ensure_all_started(:sarduty); import Ecto.Query; users = App.Repo.all(from u in App.Accounts.User, where: u.is_admin == true); IO.inspect(users)"'
```

### 4. Important Rules

- Wrap entire eval code in double quotes (`"`)
- Escape inner double quotes with backslash (`\"`)
- Chain multiple statements with semicolons (`;`)
- Use `IO.inspect()` to view results
- Use bang methods (`get!`, `update!`) for simpler error handling
- Import `Ecto.Query` when using `from` macro

## Examples

**Set user as admin:**
```bash
fly ssh console -a sarduty --machine 87ede0c01595e8 -C 'bin/sarduty eval "Application.ensure_all_started(:sarduty); user = App.Repo.get_by!(App.Accounts.User, email: \"andrew.wallwork@sfsar.ca\"); changeset = Ecto.Changeset.change(user, is_admin: true); App.Repo.update!(changeset); IO.puts(\"User updated\")"'
```

**List all admin users:**
```bash
fly ssh console -a sarduty --machine 87ede0c01595e8 -C 'bin/sarduty eval "Application.ensure_all_started(:sarduty); import Ecto.Query; admins = App.Repo.all(from u in App.Accounts.User, where: u.is_admin == true, select: {u.id, u.email}); IO.inspect(admins)"'
```

## Troubleshooting

**"could not lookup Ecto repo"**: Forgot to start the app. Add `Application.ensure_all_started(:sarduty)`.

**"app has no started VMs"**: Check `fly status`. Start machine with `fly machines start <ID>` if needed.

**Quote escaping issues**: Ensure outer quotes are `"` and inner quotes are `\"`.

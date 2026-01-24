---
name: Data Model + Migration
description: Add or change database-backed models using Ecto + SQLite conventions in this codebase.
---

## Scope

Use this skill when introducing or modifying persisted data.

## Checklist

- Generate migrations via `mix ecto.gen.migration` and update `priv/repo/migrations/*`.
- Define schemas in `lib/app/model` with `use App, :model`, explicit `field` types, and `timestamps`.
- Validate with `App.Validate` helpers and `App.Field` types (e.g. `Field.TrimmedString`).
- Avoid casting programmatically-set fields; set them explicitly on the struct when creating records.
- Use `Ecto.Changeset.get_field/2` to read changeset values (no access syntax).
- Preload associations before rendering in templates.
- Add or update fixtures in `test/support/fixtures` when tests need new data.

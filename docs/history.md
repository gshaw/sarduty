# History

The project's story, in place of a changelog: what changed, when, and why it mattered.
Newest last. Maintained by [agent_prompts/refresh-history.md](../agent_prompts/refresh-history.md).

## 2023 — Start

- **November 2023.** Generated as a Phoenix app with `phx.gen.auth`, briefly named SAR
  Task.
- **December 2023.** The core arrived in two weeks: encrypted D4H access keys, one team
  per key so any SAR team can sign up, the mileage report, a manual refresh that copies
  members, activities, and attendance into SQLite, and the first tax credit letter PDF.
  Namespaces became `App` and `Web`, DaisyUI was dropped for hand-written Tailwind, and it
  went to Fly.io.

## 2024 — Letters, then D4H v3

- **January 2024.** Tax credit letters created, stored, and emailed, ready for use on
  January 9. The team logo comes from D4H. The Fly region moved to Toronto.
- **April 2024.** The 200-hour minimum for letters was removed; hours became a filter
  instead.
- **October–November 2024.** Moved to the D4H v3 API — activities, attendance, tags, and
  the team logo — with pagination. The mileage report followed. `mise` tasks arrived.

## 2025 — Maintenance

- **January–February 2025.** D4H personal access tokens replaced API keys. `access_key`
  params are filtered from logs.
- **December 2025.** Phoenix and Tailwind upgrades, new Docker and release scripts, and
  Litestream replication with a backup script.

## 2026 — Background sync and groups

- **January 2026.** Mail moved to ZeptoMail. Copilot skills added for agents.
- **February 2026.** The refresh moved into daily Oban jobs with a team-level key (#10).
  Qualifications and awards joined the copy (#6, #12), stale attendance started being
  deleted, and a read-only MCP endpoint was added.
- **March 2026.** D4H groups synced (#16), and qualification rules for groups with a
  preview (#17).
- **September 2026.** Agent setup rebuilt to match tides: `AGENTS.md` rewritten, `docs/`,
  `agent_prompts/`, mise-based checks, and CI. `mix precommit`, which had been failing
  since the MCP and group rule commits, passes again.

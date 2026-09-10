# History

The project's story, in place of a changelog: what changed, when, and why it mattered.
Newest first. Maintained by [agent_prompts/refresh-history.md](../agent_prompts/refresh-history.md).

## 2026 — Background sync and groups

- **March.** D4H groups are synced (#16), and groups can have qualification rules with a
  preview of who would be added or removed (#17).
- **February.** The refresh moved into daily Oban jobs with a team-level D4H key (#10).
  Qualifications and awards joined the local copy (#6, #12), stale attendance started
  being deleted, and a read-only MCP endpoint was added.
- **January.** Mail moved to ZeptoMail. Copilot skills were added for agents.

## 2025 — Maintenance

- **December.** Phoenix and Tailwind upgrades, new Docker and release scripts, and
  Litestream replication with a backup script.
- **January–February.** D4H personal access tokens replaced API keys. `access_key`
  params are filtered from logs.

## 2024 — Letters, then D4H v3

- **October–November.** Moved to the D4H v3 API — activities, attendance, tags, and the
  team logo — with pagination. The mileage report followed. `mise` tasks arrived.
- **April.** The 200-hour minimum for letters was removed; hours became a filter instead.
- **January.** Tax credit letters are created, stored, and emailed, ready for use on
  January 9. The team logo comes from D4H. The Fly region moved to Toronto.

## 2023 — Start

- **December.** The core arrived in two weeks: encrypted D4H access keys, one team per key
  so any SAR team can sign up, the mileage report, a manual refresh that copies members,
  activities, and attendance into SQLite, and the first tax credit letter PDF. Namespaces
  became `App` and `Web`, DaisyUI was dropped for hand-written Tailwind, and it went to
  Fly.io.
- **November.** Generated as a Phoenix app with `phx.gen.auth`, briefly named SAR Task.

Last updated: 2026-09-10 (f9ca9e8)

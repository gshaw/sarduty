# History

The project's story, in place of a changelog: what changed, when, and why it mattered.
Newest first. Maintained by [agent_prompts/refresh-history.md](../agent_prompts/refresh-history.md).

## 2026 — Many teams, ID cards, and the door

- **October.** Teams sign themselves up, and access comes from D4H: anyone D4H makes an
  Owner or Editor logs in with an emailed or texted code (#125, #146, #150, #241). The
  copy syncs every 10 minutes instead of nightly, marks members and activities D4H
  deletes, and keeps a history of every change per member and activity (#163, #160,
  #219). Every write to D4H became a change set (#181). Attendance is taken at the door
  by scanning ID cards, with a yet-to-arrive list and no-shows, then sent to D4H after a
  review (#139, #245). Tax credit letters count hours row by row, carry a signature and
  a QR code to verify them, and go to every eligible member at once (#191–#208). An MCP
  trial lets a manager's AI agent read the team's data and propose attendance changes
  (#28, #216). A design system and writing guide reshaped every page (#131, #23), with
  a public home page, privacy and terms (#217, #210). Teams without D4H can keep their
  records in SAR Duty Records and edit them here (#266–#270).
- **September.** Member ID cards arrived, with Apple and Google Wallet passes that update
  on the phone, and a public verify site (#64–#90). Group rules can be reviewed and
  applied to D4H (#53). Mail moved to Cloudflare Email Sending (#59). Records are looked
  up through the current team, team keys are checked with D4H and never echoed, and
  errors go to Honeybadger (#43, #45, #47).
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

Last updated: 2026-10-09 (39e3370)

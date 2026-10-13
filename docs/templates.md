# Templates

<!-- cspell:ignore SFSAR -->

A template is SAR Duty's own: a named set of items with default hours, tags, and groups
to invite, applied to an activity in one step (#271, #162). D4H never sees templates.
They started as equipment "kits" (#271) and became templates on 2026-10-13, once they
held more than items. Andrew's examples on #162 show where they go next: a location, and
incident fields such as the city and primary cause.

Templates have their own menu item, `/teams/:subdomain/templates`. They live in
`templates`, `template_items`, `template_tags`, and `template_groups`, and the sync never
touches them, except that an item, tag, or group D4H deletes leaves its templates.

## What a template holds

- **Items**, each with default hours (Andrew's comment on #271), such as "Command
  response": the command truck, the command phone, and the command rate. Hours only count
  for equipment. D4H takes km for a vehicle and a count for a supply, so a template's
  vehicle lines have no hours and their usages go without a duration.
- **Tags**, such as Flat Water and Primary Hours for boat training. The picker lists the
  team's tags from the sync's copy in `tags`: with no search, the 8 its activities used
  most in the last year, and A to Z with one. D4H's API has no tag bundles
  (`resource-bundles` only groups custom fields), so the picker can't group them the way
  D4H's web app does. A template points at the local tag, so a rename shows up.
- **Groups to invite**, such as the Search Managers group for a managers' training.
  Applying the template asks each member of the group to come, the way D4H's own
  "Requested" works: it signs nobody up, and each member answers in D4H.

## Applying a template

The activity's Actions list has "Apply a template"
([ActivityTemplateLive](../lib/web/live/activity_template_live.ex)). Each template added
puts its items, tags, and groups in one list to send, so several combine. The items'
hours and a vehicle's km can change before sending, and anything can be removed.
Retired and lost items are left out, and so is any item already on the activity.

The items and tags go first, as one change set of source `equipment`
([ChangeActivityEquipment](../lib/app/operation/change_activity_equipment.ex)): one
`create_equipment_usage` row per item, as in [equipment.md](equipment.md), and one
`set_activity_tags` row.

Tags leave out any the activity has by its copied titles. Sending reads the activity's
tag ids from D4H, then sends those and the new ones, each id once
(`ChangeActivityEquipment.plan_tags/3`). D4H's `POST /{kind}s/{id}/tags` replaces the
whole list, so a list from the last sync could drop a tag someone just added. After it
applies, the new titles are copied to the activity so its page shows them.

Then the invites, as a second change set of source `template`
([InviteGroups](../lib/app/operation/invite_groups.ex)): one `create_attendance` row with
status `REQUESTED` per current member of the groups, for the activity's start and end. A
member in two groups is invited once. Anyone with attendance on the activity already, in
any status, is left out, and the applier skips anyone D4H has a row for now, since D4H
would add a second one. A published activity's attendance is locked, so it refuses the
invites; the items and tags still go. If the items or tags are refused, nobody is
invited. The invites reach the local copy on the next sync.

## Still to come

From #162: applying a template when adding an activity, which needs adding activities
for D4H teams first, and a template's location and incident fields.

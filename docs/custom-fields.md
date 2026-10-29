# Custom fields

<!-- cspell:ignore BCSARA SFSAR -->

D4H lets a team, or its organisation, add its own fields to incidents, exercises,
events, members, and equipment (#681). BCSARA's 27 incident fields, such as Primary
Cause, Agency File #, and Task Type, are on every BC team, and 19 of them are required.
SAR Duty copies the fields and their values so it can show them, flag missing required
ones, edit them, and later fill them from templates (#307).

## What is copied

- **Definitions** are copied to `custom_fields` by
  [UpsertCustomFields](../lib/app/operation/refresh_d4h_data/upsert_custom_fields.ex):
  the team's own fields and its organisation's, for events, exercises, incidents,
  members, and equipment, archived ones too. D4H's other targets (health and safety
  reports, persons involved, the team itself, incident weather) are left out. Choice
  fields keep their options in `options`. The sync's 16th list head; SAR Duty Records
  has no custom fields, so it is never asked, and its head is always empty.
- **Values** ride on the records the sync already reads: `activities.custom_values` and
  `equipment_items.custom_values`, a map of the D4H field id, as a string, to a string
  or a list of D4H option ids. They're keyed by D4H ids, not local ones, since the
  values are D4H option ids too and the copy can be rebuilt from D4H at any time. Empty
  values are left out of the map. Nil means not copied yet.
- **Member values are not copied yet.** Member fields hold year of birth, gender,
  ethnicity, medical notes, and licence numbers, and the team's key reads every one,
  RESTRICTED ones included. A team admin will pick which member fields to copy, none at
  first, and RESTRICTED ones are never offered.

## How fresh it is

D4H doesn't change a record's `updatedAt` when only its custom field values change
(tested 2026-10-28). The sync reads the open years' activities whole every 10 minutes,
so an incident's fields arrive within 10 minutes. Older activities and equipment wait
for another change to their list, or the nightly refresh.

## History

An activity's values are a tracked field. History keeps them as text by field title,
only the fields that changed: "Primary Cause changed to Dementia",
"Area cleared". The first copy of an activity's values, from nil, is the baseline and
records nothing.

## Restricted fields and organisations

D4H's RESTRICTED on a team's own field keeps it from rolling up to its organisation:
the team sees it, BCSARA doesn't (a South Fraser team admin, 2026-10-28). South
Fraser's one is "SFSAR Custom PRIVATE", working notes on a task report. So:

- **Team admins see a RESTRICTED field, members don't.** D4H asks for an extra
  permission to see one.
- **Nothing an organisation sees reads RESTRICTED values**: the org space
  ([organizations.md](organizations.md)), org reports such as unique file numbers
  (#363), and the MCP. A report across an organisation's teams uses its own,
  unrestricted fields, which mean the same thing on every team.
- Member fields are different: a RESTRICTED member field is never copied at all.

## D4H's API

- `GET /custom-fields` lists the team's fields and its organisation's, with `owner`
  saying which.
- Writes are `customFieldValues: [{id, value}]` on create and PATCH of events,
  exercises, and incidents, and on PATCH of members and equipment. A PATCH that sends
  one field keeps the others. `value: null` clears a text or choice field; `[]` gets a
  400 (tested on a member, 2026-10-28).
- D4H checks required fields when an incident is published or approved, not when it is
  saved: a new incident with them blank saves in D4H.

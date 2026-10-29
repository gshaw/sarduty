# Custom fields

<!-- cspell:ignore BCSARA SFSAR -->

D4H lets a team, or its organization, add its own fields to incidents, exercises,
events, members, and equipment (#681). BCSARA's 27 incident fields, such as Primary
Cause, Agency File #, and Task Type, are on every BC team, and 19 of them are required.
SAR Duty copies the fields and their values so it can show them, flag missing required
ones, edit them, and later fill them from templates (#307).

## What is copied

- **Definitions** are copied to `custom_fields` by
  [UpsertCustomFields](../lib/app/operation/refresh_d4h_data/upsert_custom_fields.ex):
  the team's own fields and its organization's, for events, exercises, incidents,
  members, and equipment, archived ones too. D4H's other targets (health and safety
  reports, persons involved, the team itself, incident weather) are left out. Choice
  fields keep their options in `options`. The sync's 16th list head; SAR Duty Records
  has no custom fields, so it is never asked, and its head is always empty.
- **Values** ride on the records the sync already reads: `activities.custom_values` and
  `equipment_items.custom_values`, a map of the D4H field id, as a string, to a string
  or a list of D4H option ids. They're keyed by D4H ids, not local ones, since the
  values are D4H option ids too and the copy can be rebuilt from D4H at any time. Empty
  values are left out of the map. Nil means not copied yet.
- **Member values are copied only for the fields a team admin picks**, on team
  settings' Members tab, none at first. Member fields hold year of birth, gender,
  ethnicity, medical notes, and licence numbers, and the team's key reads every one,
  RESTRICTED ones included. RESTRICTED member fields are never offered: the tab counts
  them and says they stay private. `members.custom_values` holds only the picked
  fields ([SaveTeamMemberFields](../lib/app/operation/save_team_member_fields.ex)).
  Saving clears every member's values and reads the members at once, so the copy after
  a change is a new baseline and an unpicked field leaves nothing behind.

## Where they show

[CustomField.rows/4](../lib/app/model/custom_field.ex) picks what a page shows, and
[CustomFields](../lib/web/components/custom_fields.ex) shows it as a detail list.

- **An activity's page** has a section named for its kind, "Incident fields", under
  the description: every field with a value, in D4H's order. Team admins also see
  RESTRICTED fields and each required field left empty, marked Missing. Members see
  the rest, as they see tags.
- **An equipment item's page**, for team admins, has Equipment fields.
- **A member's page**, for team admins, lists the copied member fields in the sidebar.
  A member sees their own on Your membership's Contact details, only the ones D4H lets
  a member see (`member_privacy` viewable or editable). Members never see another
  member's.

## How fresh it is

D4H doesn't change a record's `updatedAt` when only its custom field values change
(tested 2026-10-28). The sync reads the open years' activities whole every 10 minutes,
so an incident's fields arrive within 10 minutes. Older activities and equipment wait
for another change to their list, or the nightly refresh.

## History

An activity's values are a tracked field. History keeps them as text by field title,
only the fields that changed: "Primary Cause changed to Dementia",
"Area cleared". A member's keep the field titles alone, never the values, as for
contact details: "Radio Call Sign changed". The first copy of a record's values, from
nil, is the baseline and records nothing.

## Restricted fields and organizations

D4H's RESTRICTED on a team's own field keeps it from rolling up to its organization:
the team sees it, BCSARA doesn't (a South Fraser team admin, 2026-10-28). South
Fraser's one is "SFSAR Custom PRIVATE", working notes on a task report. So:

- **Team admins see a RESTRICTED field, members don't.** D4H asks for an extra
  permission to see one.
- **Nothing an organization sees reads RESTRICTED values**: the org space
  ([organizations.md](organizations.md)), org reports such as unique file numbers
  (#363), and the MCP. A report across an organization's teams uses its own,
  unrestricted fields, which mean the same thing on every team.
- Member fields are different: a RESTRICTED member field is never copied at all.

## D4H's API

- `GET /custom-fields` lists the team's fields and its organization's, with `owner`
  saying which.
- Writes are `customFieldValues: [{id, value}]` on create and PATCH of events,
  exercises, and incidents, and on PATCH of members and equipment. A PATCH that sends
  one field keeps the others. `value: null` clears a text or choice field; `[]` gets a
  400 (tested on a member, 2026-10-28).
- D4H checks required fields when an incident is published or approved, not when it is
  saved: a new incident with them blank saves in D4H.

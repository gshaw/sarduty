# Custom fields

<!-- cspell:ignore BCSARA SFSAR -->

D4H lets a team, or its organization, add its own fields to incidents, exercises,
events, members, and equipment (#681). BCSARA's 27 incident fields, such as Primary
Cause, Agency File #, and Task Type, are on every BC team, and 19 of them are required.
SAR Duty copies the fields and their values so it can show them, flag missing required
ones, edit them, and fill them from templates (#307).

## What is copied

- **Definitions** are copied to `custom_fields` by
  [UpsertCustomFields](../lib/app/operation/refresh_d4h_data/upsert_custom_fields.ex):
  the team's own fields and its organization's, for events, exercises, incidents,
  members, and equipment, archived ones too. D4H's other targets (health and safety
  reports, persons involved, the team itself, incident weather) are left out. Choice
  fields keep their options in `options`, each with the team or organization that
  added it: a team can add choices to its organization's field. Each field also keeps
  when it was added (`d4h_created_at`), and D4H's `searchable` and `frozen`, which
  #724 needs. The sync's 16th list head. SAR Duty Records serves them in D4H's shape
  too (#1003): a Records team does everything a D4H team does with fields.
- **Bundles** are D4H's resource bundles, named groups of one kind's fields, such as
  BCSARA's KMS Data on incidents (#872). A field is in one bundle or none, and a
  bundle holds one kind's. They're copied to `custom_field_bundles` with the fields,
  from `GET /resource-bundles`, and a field points at its own with `bundle_id`. A team's
  list holds its organization's bundles too. A bundle D4H deleted goes, and its fields
  join none. A bundle has no hint, and D4H's API can create one but never rename or
  delete it. The bundles are read with the fields, so a renamed bundle waits for a field
  change or the nightly refresh.
- **Values** ride on the records the sync already reads: `activities.custom_values`,
  `members.custom_values`, and `equipment_items.custom_values`, a map of the D4H field id, as a string, to a string
  or a list of D4H option ids. They're keyed by D4H ids, not local ones, since the
  values are D4H option ids too and the copy can be rebuilt from D4H at any time. Empty
  values are left out of the map. Nil means not copied yet.
- **Every member field's values are copied**, RESTRICTED ones too (decided 2026-11-12,
  #1056): SAR Duty copies everything the access key reads and doesn't judge which data a
  team should have. A key that can't read a restricted value brings none. Until #1056 a
  team admin picked which member fields to copy with a Copy box, and RESTRICTED ones
  never were. The migration that dropped the box cleared every member's values and
  forgot the members list head, so the next sync, within 10 minutes, read the members
  whole as a baseline and history didn't call every newly kept field a change.
- **Who sees a member's values** has one home, `CustomField.member_fields/2`: a team
  admin gets every live member field; a member gets their own where `member_privacy` is
  viewable or editable. Restricted is never asked on a member field. Nothing an
  organization or an AI agent sees reads a member's values.

## Where they show

[CustomField.rows/4](../lib/app/model/custom_field.ex) picks what a page shows, and
[CustomFields](../lib/web/components/custom_fields.ex) shows it.

Every list of fields groups them by bundle, through one function,
`CustomField.grouped/2`: the fields in no bundle first, with no heading, then each
bundle under its title, by D4H's `ordering` and then its id. Fields keep D4H's
`ordering` inside each group. With no bundles a list looks as it did before. The
Fields tabs, Change fields, a template's fields, and Your membership's member fields
all use it; so will #875's field picker. The Missing block stays one list at the top of
a Fields tab, so the required fields aren't spread across four headings.

D4H's own order is unknown: all 8 of BCSARA's bundles have `ordering` 0, and D4H
numbers an organization's fields in one run across its bundles while a team's own
start again at 0 (read on South Fraser, 2026-11-12). So the order above is a fallback
until someone matches D4H's incident form.

A record's custom fields are its **Fields tab**, `/fields`, a table with each field's
name beside its value (decided 2026-10-28, #705). They were in the sidebar, after the
facts, until a BC incident's 27 ran it 3 screens long and pushed Actions to the bottom.
So every record's sidebar is its facts, then Actions. The tab shows only when the record
has a field to show, as a member's Equipment tab shows only when they hold something, or
for a team admin when its kind has fields to fill in ([below](#changing-them)). It's
named Fields, not
"Incident fields": the page already says what the record is, and the name doesn't change
with the kind.

- **An activity's** Fields tab, after Members and Equipment, shows every field with a
  value, in D4H's order. Team admins also see RESTRICTED fields, and on a draft incident
  each required field left empty, marked Missing ([below](#missing-required-fields)):
  the missing ones come first, under "9 of 19 needed to publish are empty.", and the
  tab's name carries the count in amber. Members see the rest, as they see tags.
- **An equipment item's**, for team admins: its page gets Activities and Fields tabs,
  in the main column under what's inside it.
- **A member's**, for team admins, before History: every member field, restricted ones
  too. A member sees their own on Your membership's Contact details, only the ones D4H
  lets a member see (`member_privacy` viewable or editable). Members never see another
  member's.
- **Reports** read the same fields as the Fields tab, by title in backticks:
  `` `Primary Cause` `` (#840, [reports.md](reports.md#custom-fields)). Members read an
  activity's unrestricted ones; a member's and an item's are for team admins, every
  member field included.

## The Fields page

What each field means lives in its hint and its bundle, not its title: "If unknown,
enter 999" on a number field changes how a report sums it. So team settings has a
**Fields** tab, `/teams/:subdomain/settings/fields`, after Members (#872).

The tab is an index to scan, one kind at a time: counts for incidents, exercises,
events, members, and equipment switch between them (`?kind=member`). The team's own
fields come first, under "Coast Range SAR's fields", then its organization's, under
"WESARA's fields", so step 4 of #1056 can let a team change its own. Each is a row link,
by bundle (decided 2026-11-12, #1056): the name, its type in grey, at most one tag, and
the first line of its hint. On a member field the grey text adds who sees it: Team
admins only, Members see their own, or Members change their own. The tag is Needed to
publish on an activity's required field, else Restricted on an activity or equipment
field; a restricted member field is a normal row. A kind's archived fields wait at its
foot, closed. Nothing on the tab is a setting: #1056 took out the member fields' Copy
boxes.

A row opens **its own page**, `/teams/:subdomain/settings/fields/:id`, a detail list in
one order that leaves out what a field lacks: What it means, Type (Text and Long text
apart), On with its bundle, Added by, Needed to publish, Members, Restricted, Choices,
the choices a team added to an organization's field under the team's name, and Archived
choices. Added by, Needed to publish, Members, and Restricted each carry a line on what
they mean: an organization's field is on every team so its reports read it the same way,
and only the organization changes it. A RESTRICTED activity field says only team admins
see its values; on a member field it says restricted changes nothing in SAR Duty.

Decided 2026-11-12: the first version put every field's hint and choices on the tab,
and with BCSARA's 40-odd Activity choices it read as a wall of text. Folding long lists
wasn't enough. Never a select for choices either: nothing on the page can be changed.

It's read only: fields change in D4H, and editing them here is #724. D4H's web address
for its fields page isn't known, so the page names D4H without a link.

**An organization's Fields tab**, `/orgs/:slug/settings/fields`, after Hours tags, is
for its organization admins: its own fields, laid out the same way, each with its own
page, `/orgs/:slug/settings/fields/:id`, read from its teams' copies
(`CustomField.merge_copies/1`). D4H gives every team its organization's fields, so
there's no list of teams; a choice a team added names the team. A
RESTRICTED field shows what it is, never values: the page shows no values at all.

The report editor's Custom fields, the Agents tab, and an empty Fields tab link to the
team's page with "What each field means", for team admins.

## Missing required fields

D4H won't publish an incident until its required fields are filled in. So a required
field left empty is flagged only on a draft incident (`Activity.flag_missing_fields?/1`,
decided 2026-10-28): the activity's Fields tab marks it Missing for team admins, and Needs
attention lists finished drafts with one, "2 draft activities are missing required
fields", linking to the built-in report Activities missing required fields
(`Activity.missing_required_fields/1`, the same rule as a query). A published incident
got past D4H, so whatever is empty there is optional in practice, and flagging it is
noise. Exercises and events aren't flagged: D4H's check is tested only on incidents.
An activity whose values aren't copied yet isn't counted. Records refuses to publish
such an incident with a 409, as D4H does, and the page shows its title (#1003).

Later, a team may pick which fields it requires, as it picks member fields, for the
fields D4H doesn't enforce.

## Changing them

A record's fields have their own page, **Change fields**, `/fields/edit`, reached from
Change fields in its Actions, after the record's own Change link, and at the foot of its
Fields tab (decided 2026-10-29, #705). Before, Add
activity and Change activity held every field of the kind, and a BC incident's ran the
form six screens long, with the title, times, and address lost above them. Change
activity now has a Fields section with the tab's count and the same link. Add activity
has none: the fields wait until the activity exists, and a template fills most of
them (#307, [templates.md](templates.md#fields)).

- **An activity's**, for team admins, its kind's fields. A published one is locked, as
  for its other details.
- **A member's**, every member field, restricted ones too.
- **An equipment item's**, every equipment field.

Each field is its type's input: text, a box for text areas, a number, a date or time, a
select (a combobox past 10 options), or boxes to tick. On an activity a required one
is tagged Needed to publish. On a draft incident one left empty is tagged Missing, with
the error's bar in amber (`field-missing`), and a count over the form says saving still
works; both change as the person types. Never a red error: D4H saves them blank and
checks them only when it publishes. An archived option shows
only while it is chosen. A team admin gets the Fields tab, with its link, whenever the
record's kind has fields, so an empty one can be filled in; it says "No fields filled
in."

[SaveCustomFields](../lib/app/operation/save_custom_fields.ex) sends only the fields
that changed, as `custom_values` on one change set row (nil clears one), and the adapter
turns them into `customFieldValues`: `update_activity`, `update_member`, or
`update_equipment_item`. On a D4H team a member or item row may send its custom fields
with only the other fields D4H's PATCH takes ([ApplyEdit](../lib/app/operation/apply_edit.ex)). The copy takes the
values it sent, since the sync after the write may not read them back. History says
"Fields changed in SAR Duty", never the values.

## How fresh it is

D4H doesn't change a record's `updatedAt` when only its custom field values change
(tested 2026-10-28). SAR Duty Records does, so its heads see the change. The sync reads the open years' activities whole every 10 minutes,
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
- Member fields are different: RESTRICTED changes nothing on one in SAR Duty. Team
  admins see every member's values, members their own as member privacy allows, and an
  organization never a person's (#1056).

## D4H's API

- `GET /custom-fields` lists the team's fields and its organization's, with `owner`
  saying which. Each has `bundle: {id}` or null, `createdAt`, `searchable`, and
  `frozen`, and each option its own `owner` (all filled on South Fraser, 2026-11-12).
- `GET /resource-bundles` lists the bundles: `id`, `title`, `owner`, `ordering`, and
  `target.subResourceType`, the kind of record its fields are on. South Fraser sees 8,
  all BCSARA's: 3 on incidents, 1 on members, 4 on health and safety reports.
- Writes are `customFieldValues: [{id, value}]` on create and PATCH of events,
  exercises, and incidents, and on PATCH of members and equipment. A PATCH that sends
  one field keeps the others. `value: null` clears a text or choice field; `[]` gets a
  400 (tested on a member, 2026-10-28).
- D4H checks required fields when an incident is published or approved, not when it is
  saved: a new incident with them blank saves in D4H.

## SAR Duty Records

Records is the test bed (Gerry, 2026-11-07): a Records team does everything a D4H team
does with fields, and SAR Duty has no branch for it (#1003). Records serves
`GET /custom-fields`, `GET /resource-bundles` (#872), and the values on each record in
D4H's shape, takes the same
writes, and refuses publishing an incident with a required field empty with a 409, as
D4H does. Fields match across services by kind and title, never by id: each service
picks its own.

Records makes no fields over its API yet; its own store does, for Try a demo's cast
([demo.md](demo.md#the-cast)), the dev teams, and its own sample. A team adds its own
fields later (#724).

# Custom fields

<!-- cspell:ignore BCSARA SFSAR -->

D4H lets a team, or its organization, add its own fields to incidents, exercises,
events, members, equipment (#681), and the team itself (#1056). BCSARA's 27 incident fields, such as Primary
Cause, Agency File #, and Task Type, are on every BC team, and 19 of them are required.
SAR Duty copies the fields and their values so it can show them, flag missing required
ones, edit them, and fill them from templates (#307).

## What is copied

- **Definitions** are copied to `custom_fields` by
  [UpsertCustomFields](../lib/app/operation/refresh_d4h_data/upsert_custom_fields.ex):
  the team's own fields and its organization's, for events, exercises, incidents,
  members, equipment, and the team itself, archived ones too. D4H's other targets
  (health and safety reports, persons involved, incident weather) are left out. Choice
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
  `members.custom_values`, and `equipment_items.custom_values`, and the team's own on
  `teams.custom_values` ([below](#fields-on-the-team-itself)), a map of the D4H field id, as a string, to a string
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
  too. A member sees their own on Your membership's Change fields, only the ones D4H
  lets a member see (`member_privacy` viewable or editable), and changes the editable
  ones there ([below](#a-members-own-answers)). Members never see another member's.
- **Reports** read the same fields as the Fields tab, by title in backticks:
  `` `Primary Cause` `` (#840, [reports.md](reports.md#custom-fields)). Members read an
  activity's unrestricted ones; a member's and an item's are for team admins, every
  member field included.

## The Fields page

What each field means lives in its hint and its bundle, not its title: "If unknown,
enter 999" on a number field changes how a report sums it. So team settings has a
**Fields** tab, `/teams/:subdomain/settings/fields`, after Members (#872).

The tab is an index to scan, one kind at a time: counts for incidents, exercises,
events, members, equipment, and the team switch between them (`?kind=member`). The team's own
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

With a key that can change fields, the tab says the team adds and changes its own
fields here, and has **Add field** beside it; a team's own field's page has **Change
field**, or **Restore field** when it's archived ([below](#adding-and-changing-fields)).
An organization's field, a `frozen` one, and a key that can't get neither. A D4H key
that can't (an Editor's) keeps the read-only tab, with one paragraph saying to change
them in D4H or save an Owner's key, linking the Access key tab. D4H's web address for
its fields page isn't known, so the page names D4H without a link.

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

## A member's own answers

D4H lets a member change their own answer to a member field set to `editable` (#1056
step 2). On Your membership's Change fields, `/teams/:subdomain/me/fields`
([MeFieldsLive](../lib/web/live/me_fields_live.ex)), the team's own fields come first,
then its organization's, each under its name and logo, as on the Fields tab. Each keeps
D4H's order: an editable field is its type's input, the component a team admin's Change
fields uses, and a viewable one shows its value in place, or None. A hidden one never
shows. Your membership links to it only when the
team has fields a member sees. A key that can't fill in fields
(`Team.d4h_can?(team, :field_values)` false) shows them all as values, with no Save.

Save fields sends the fields that changed on one `update_member` row, through
[SaveOwnDetails](../lib/app/operation/save_own_details.ex), which reads the diff from `SaveCustomFields.changes/3`. The fields it reads are
`SaveOwnDetails.fields/1`, looked up through the member's team on every save, so a
viewable or hidden field's id posted by the client is never sent. The copy takes the
values sent, as for a team admin's change. History says "Fields changed in SAR Duty",
never the values. A team admin viewing as the member can't save, as on the other Change
pages.

## Fields on the team itself

D4H's sixth kind is the team (#1056 step 5). BCSARA has five on its teams: Duty Phone,
Mailing Address, City/Town, Postal Code, and Team Email Contact, and an organization's
forms need them. The Fields tab has a Team count with the same rows and field pages,
and Add field's On list has Team.

- **Copied** from `GET /teams/{id}`'s `customFieldValues` into `teams.custom_values`,
  keyed like a record's, by RefreshTeamDetails at the start of every full refresh. The
  team's record has no list head, so the syncs never read them, and a value changed in
  D4H waits for the next full refresh ([d4h-sync.md](d4h-sync.md#custom-fields)).
- **Shown** on General, `/teams/:subdomain/settings`, under the team's details: the
  team's own fields under its name, then its organization's, each a Fields table as a
  record's Fields tab draws it. **Change fields** in General's Actions opens
  `/teams/:subdomain/settings/fields/edit`. That is
  [CustomFieldsFormLive](../lib/web/live/custom_fields_form_live.ex) for the team, and
  goes back to General.
- **Saved** by [SaveCustomFields](../lib/app/operation/save_custom_fields.ex) as one
  change set row, `update_team` with only `custom_values`, sent as `PATCH /teams/{id}`
  (`D4H.update_team/2`). Records takes it. On D4H it is untried until Gerry's live
  check on South Fraser. The copy takes what was sent; no sync follows.
- **Who sees.** Team admins: General is theirs. Restricted works as on an activity's
  field: the box is on Add field and Change field for the team, and nothing an
  organization sees reads a restricted one. Members never see the team's values.
  Reports and agents don't read them yet.

City and Postal code stay on General's form until the organization's forms read its own
fields, with the forms work.

## Adding and changing fields

A team admin adds, changes, archives, restores, deletes, and reorders the team's own
fields (#1056 step 4). The organization's stay read only: D4H gives a team's key no way
to change them. Every write is a change set ([change-sets.md](change-sets.md)), and the
copy takes what D4H answers with, so the next page shows it without waiting for the
sync.

- **Add field**, `/teams/:subdomain/settings/fields/new?kind=incident`, opens on the
  kind in view: On, Name, Type (the combobox chore categories use, with a line under each
  type), Choices on One choice and Several choices, Units on a Number, What it means (the
  hint), and Bundle, a combobox of the team's own bundles of the kind that takes a new
  name. Needed to publish and Restricted show on activity kinds only, and Each member's
  own answer (Hidden from them, They see it, They see and change it) on members only.
- **Change order**, `/teams/:subdomain/settings/fields/order?kind=incident`, lists the
  team's own live fields of one kind, from Change order on the Fields tab when the kind
  has 2 or more. Drag a row by its grip, or use Move up and Move down; Save order sends
  it. The organization's fields keep their own order.
  [FieldOrderLive](../lib/web/live/settings/field_order_live.ex) and the choices on Add
  field and Change field share the drag list, `/styles/drag-list`, which equipment
  checklists (#407) can reuse.
- **Change field**, `/teams/:subdomain/settings/fields/:id/edit`, is the same form
  without On and Type, which are facts in the lead with how many records have an answer:
  "One choice, on incidents. 38 incidents have an answer." A choice the field has is
  dragged into a new order, and archived or restored, shown greyed while archived; a new
  one is removed. Archive field keeps every answer; a field no record has answered
  offers Delete field in its place, red with a confirm. Both pages are
  [FieldFormLive](../lib/web/live/settings/field_form_live.ex), and refuse a field the
  team can't change.

These are the operations they call.

- **Who.** `CustomField.team_changes?/2`: the team's own field, not `frozen`, with a key
  that can change fields (`Team.d4h_can?(team, :custom_fields)`). An Editor's D4H key
  can't; a Records team always can.
- **Adding** is one operation,
  [CreateCustomField](../lib/app/operation/create_custom_field.ex), which Add field and
  #875's import templates both call. The rules are
  [CustomFieldFormViewModel](../lib/app/view_model/custom_field_form_view_model.ex)'s:
  a name of 1 to 150 characters with no `|`, that no other live field of the kind has,
  the team's or its organization's, ignoring case; one of D4H's 8 types; at least 1
  live choice on a choice field, each named once; units of up to 10 characters, sent on
  a number only. A new field goes after the team's others of its kind.
- **Settings by kind.** Needed to publish goes on incidents, exercises, and events only.
  Restricted is the team admin's choice on an activity field or one on the team itself
  (`CustomField.restricted_matters?/1`), and always sent, since
  D4H's default is RESTRICTED: RESTRICTED on a member field, the safer choice inside
  D4H, and UNRESTRICTED on equipment (decided 2026-11-13). Neither changes anything in
  SAR Duty, and changing a member or equipment field never changes it. A new member
  field starts hidden from members, D4H's default.
- **Bundles.** A field goes in one of the team's own bundles of its kind, by title, or a
  new name, which adds the bundle first in the same set. D4H's API adds a bundle but
  can't rename or delete one, so SAR Duty doesn't either, on Records too.
- **Changing**, [ChangeCustomField](../lib/app/operation/change_custom_field.ex), sends
  only what changed. Kind and type never change: D4H's PATCH takes neither. Choices are
  renamed, reordered, archived, restored, and added, a row each; D4H has no DELETE for
  one. A choice id the field doesn't have is ignored. Archive keeps every answer.
- **Deleting**, [DeleteCustomField](../lib/app/operation/delete_custom_field.ex), only
  when no record has an answer: `CustomField.answer_count/1` counts the kind's records in
  the copy, and one whose values aren't copied yet (nil) counts as having one. Otherwise
  Archive.
- **Order**, [ReorderCustomFields](../lib/app/operation/reorder_custom_fields.ex), is
  the team's own live fields of one kind, numbered from 0 into D4H's `ordering`: one set
  with a row for each field that moved. Where they sit among the organization's on a
  record stays the fallback [above](#where-they-show).

The adapter's calls, under `/v3/team/{id}/`, on D4H and Records alike:
`create_custom_field/2` (`POST /custom-fields`), `update_custom_field/3` (`PATCH`, never
with `type`, `targetResourceType`, or `options`), `delete_custom_field/2` (`DELETE`, a
404 counting as deleted), `create_custom_field_option/3` and
`update_custom_field_option/3` (`/custom-field-options`), and
`create_resource_bundle/4` (`POST /resource-bundles`). Records' `bin/check-sarduty`
checks each.

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
- A field on the team itself is like an activity's: an organization reads only the
  unrestricted ones ([above](#fields-on-the-team-itself)).

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
- `GET /teams/{id}` has the team's own values as `customFieldValues`. `PATCH
/teams/{id}` with only `customFieldValues` is untried on D4H (#1056 step 5).
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

Records takes the same field, choice, and bundle writes as D4H
(gshaw/sarduty-records#36 and #37), so a Records team adds and changes its own fields
as a D4H team does ([above](#adding-and-changing-fields)). Its own store also makes
fields for Try a demo's cast ([demo.md](demo.md#the-cast)), the dev teams, and its own
sample. Coast Range SAR's cast has WESARA's 5 team fields, with no values. Records
serves the team's own values on `GET /teams/{id}` and takes `PATCH /teams/{id}` with
only `customFieldValues`; its `bin/check-sarduty` checks `update_team/2` and
`fetch_team/1`.

# Templates

<!-- cspell:ignore SFSAR -->

A template is SAR Duty's own: a named set of items with default hours, tags, and groups
whose members it adds, applied to an activity in one step (#271, #162). D4H never sees templates.
They started as equipment "kits" (#271) and became templates on 2026-10-13, once they
held more than items. Since #307 a template for one kind of activity also holds values
for that kind's D4H custom fields, such as an incident's primary cause and requesting
agency. Since #746 a template also holds the [details](#activity-details) of the
activity it starts.

Templates have their own menu item, `/teams/:subdomain/templates`. A template's page,
`/templates/:id`, shows everything it adds on one page, since you read a template whole
before applying it (decided 2026-10-29, over tabs). Items, groups, and fields each
have their own link at their foot, to a page of its own that saves only that part
(#307): Change items, Change groups, and Change fields (`/items/edit` and so on), or Add
when the part is empty. The description comes first, then the tags, and Change tags is
in Actions, as on the activity. Change fields shows only when the kind has fields; a
template for any kind says to pick one. The details sit beside Kind, and Change details
(`/details/edit`) is in Actions. Actions also hold Change template for the name and kind
(`/edit`) and Delete template. Add template asks for the name and kind, then opens the template's
page. Delete template opens the confirm dialog, with no
page (#714). One form for everything ran a BC incident's template many screens long. They live in
`templates` (with `activity_kind`, `custom_values`, and the details), `template_items`,
`template_tags`, and `template_groups`, and the sync never
touches them, except that an item, tag, or group D4H deletes leaves its templates.

## What a template holds

- **Items**, each with default hours (Andrew's comment on #271), such as "Command
  response": the command truck, the command phone, and the command rate. Hours only count
  for equipment. D4H takes km for a vehicle and a count for a supply, so a template's
  vehicle lines have no hours and their usages go without a duration.
- **Tags**, such as Flat Water for boat training. Never the team's Primary or Secondary
  Hours tag: the details' Tax credit hours sets it, so Change tags doesn't offer them
  and saving drops them (`SaveTemplate.taggable/2`). The picker lists the
  team's tags from the sync's copy in `tags`: with no search, the 8 its activities used
  most in the last year, and A to Z with one. D4H's API has no tag bundles
  (`resource-bundles` only groups custom fields), so the picker can't group them the way
  D4H's web app does. A template points at the local tag, so a rename shows up.
- **Groups**, such as the Search Managers group for a managers' training. Applying the
  template adds each member of the group as No reply, the way D4H's own "Requested"
  works: it signs nobody up and emails nobody, and each member answers.
- **A kind and fields** (#307): Incident, Exercise, Event, or Any kind. A template with a
  kind shows that kind's D4H custom fields ([custom-fields.md](custom-fields.md)), the
  same inputs as an activity's Change fields, and keeps the filled ones in `custom_values`, keyed by
  D4H field id as on activities. Any kind holds no values, and changing the kind drops
  the old kind's. RESTRICTED fields are offered: templates are for team admins only. A
  field D4H deletes is ignored, since only the kind's live fields are read.
- **Activity details** (#746), below.

## Activity details

What a template starts on Add activity: a title, a start time and a length, an address,
tax credit hours, and a description, on Change details in the Add activity form's order
and with its labels, less the date. Every detail is optional. A blank title uses the
template's name. Tax credit hours has no blank: Primary, as on the activity form. It
sets the Primary Hours or Secondary Hours tag as the activity form does. The length is
in hours ("2.5"), as Change items takes them, and shows as 2h 30m. The kind stays on
Change template, since it also picks the fields. The templates list has a Start column,
start time and length, blank for a template with neither.

The details only fill Add activity. Applying a template leaves them out: it never changes
an activity's title, time, or address.

When the details came (2026-10-30), each template's hours tag moved into Tax credit hours
and left its tags. A template with neither tag got Primary.

## Applying a template

The activity's Actions list has "Apply a template"
([ActivityTemplateLive](../lib/web/live/activity_template_live.ex)). Each template added
puts its fields, items, tags, and groups in one list to send, so several combine. The items'
hours and a vehicle's km can change before sending, and anything can be removed.
Retired and lost items are left out, and so is any item already on the activity.

The template's [fields](#fields) go first. Then the items and tags, as one change set of source `equipment`
([ChangeActivityEquipment](../lib/app/operation/change_activity_equipment.ex)): one
`create_equipment_usage` row per item, as in [equipment.md](equipment.md), and one
`set_activity_tags` row.

Tags leave out any the activity has by its copied titles. Sending reads the activity's
tag ids from D4H, then sends those and the new ones, each id once
(`ChangeActivityEquipment.plan_tags/3`). D4H's `POST /{kind}s/{id}/tags` replaces the
whole list, so a list from the last sync could drop a tag someone just added. After it
applies, the new titles are copied to the activity so its page shows them.

Then the groups' members, as a second change set of source `template`, through the same
operation as the activity's Add members page
([InviteMembers](../lib/app/operation/invite_members.ex), #564): one `create_attendance`
row with status `REQUESTED` per current member of the groups who is a person, for the
activity's start and end. A member in two groups is added once. Anyone with attendance
on the activity already, in any status, is left out, and so is anyone away on the
activity's day; the result says how many were away ("1 member away on Oct 30 was left
out."). The applier skips anyone D4H has a row for now, since D4H would add a second
one. The rows D4H took go into the copy at once.

Members are only added before the start. A template applied after an activity, to log a
truck's hours, sends its items and tags and leaves its groups out: "3 items added. Its
groups were left out: the activity has started." On a published activity the items and
tags still go and nobody is added. If the items or tags are refused, nobody is added.

### Fields

A template's values fill in only the fields the activity has empty, as the copy has them
([SaveCustomFields.fill_empty/4](../lib/app/operation/save_custom_fields.ex)). Values for
another kind's fields are left out, so every template is listed whatever its kind. When
two templates fill one field, the first one added wins. A choice D4H has archived or
deleted since the template was saved is left out. Each field to fill is a row with a
Remove button. On a published activity the fields are left out, with a line saying so:
D4H locks them, as for Change fields.

The fields go first, as Change fields sends them: one `update_activity` row with only
`custom_values`, applied through `SaveCustomFields.call/5`, then the copy takes the
values. If D4H refuses them, nothing else is sent. The flash starts "2 fields filled
in.", and if the items or tags are refused after the fields went, the page leaves with
that line before the error, as for a refused invite.

## Still to come

From #307 and #747: picking a template on Add activity, so it fills the form from the
details and applies the rest when saving.

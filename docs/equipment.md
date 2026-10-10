# Equipment

<!-- cspell:ignore SFSAR -->

Equipment in SAR Duty (#271): a copy of a team's D4H items, the items on each activity,
and kits. This first step adds equipment to activities. Moving items, check-out, and
checklists come later.

## What SFSAR's D4H showed

Read from South Fraser's D4H on 2026-10-10, read-only:

- 1,136 items: 1,112 equipment, 17 supplies, 7 vehicles. 60 are retired and 19 lost.
- **D4H nests items through `location`, not `parents`.** `parents` is always empty. An
  item's `location` is a D4H location (5: the yard, the office, and a "Costing"
  location for rate items), another item (497 items: drawers in trucks, kits in
  drawers), or a member (216 items).
- 399 usages in the last 12 months, on 71 activities, almost all incidents. Most
  activities have 2 to 10 items. Only 4 sets repeat exactly.
- **SFSAR logs what went out, not what's in it.** The common usages are the trucks, the
  command phone, rate items ("SFSAR Command Rate"), the logistics trailer and its
  generator, and thermal cameras. Nobody logs a truck's 58 drawers and contents. So
  adding a truck adds the truck, not everything inside it.
- Equipment usages carry minutes (60 to 600, most often 120). Vehicles carry no km.

## Kits

A kit is SAR Duty's own: a named set of items, each with default hours (Andrew's comment
on #271). It is how a team adds the gear that goes out together, such as "Command
response" (the command truck, the command phone, and the command rate), in one step.
D4H never sees kits; adding one writes one usage per item. Kits live in `kits` and
`kit_items` and are never touched by the sync, except that an item D4H deletes leaves
its kits.

Hours only count for equipment. D4H takes km for a vehicle and a count for a supply, so
a kit's vehicle lines have no hours and their usages go without a duration.

## Adding equipment to an activity

The activity page has an Equipment section. "Add equipment" opens a page that builds a
list to send, from:

1. **Same as last incident** (or exercise, or event): the items on the newest earlier
   activity of the same kind that has any, with their minutes.
2. **Kits**, with each line's default hours.
3. **A search** by name, barcode, or serial. A found item starts at the activity's
   length.

Retired and lost items are left out, and so is any item already on the activity. Each
line's hours can change before sending. Sending is a change set of source `equipment`
([ChangeActivityEquipment](../lib/app/operation/change_activity_equipment.ex)), one
`create_equipment_usage` row per item. The applier reads the activity's usages first and
skips an item D4H has on it now, since D4H would count it twice. A published activity
still takes equipment. Removing an item is a `delete_equipment_usage` row. After either,
the activity's usages are read back from D4H.

## The copy

The nightly refresh copies items and usages after groups, and the sync every 10 minutes
watches `equipment` and `equipment-usages` like the other small lists: see
[d4h-sync.md](d4h-sync.md). Items and usages D4H stops listing are deleted. A D4H team
without the equipment module answers 403, and a team on SAR Duty Records has no
equipment, so neither gets the pages or the stages.

## Still to come from #271

- Moving an item, and check-out as a move to a member.
- Checklists, which live in SAR Duty since D4H's API can't create inspections.
- Scanning a barcode on a phone. The search takes a typed barcode today.
- Km for vehicles, perhaps from the mileage report.

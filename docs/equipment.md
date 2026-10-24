# Equipment

<!-- cspell:ignore SFSAR -->

Equipment in SAR Duty (#271): a copy of a team's D4H items and the items on each
activity. Templates, which add items, tags, and invites in one step, are in
[templates.md](templates.md). This first step adds equipment to activities. Moving items, check-out, and
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
- **Barcodes** (read 2026-10-11): 648 items have one, all different, and 607 of those
  are in service. 473 are the team's own tags, `SF` and digits (SF0119). Another 76 are
  names such as "Manta 01" and "Vertex 10", 20 are like "65#01", and about 45 look like
  makers' codes. 4 are 12 or 13 digits, so UPC or EAN. Lowercase letters, spaces, and
  "#" rule out plain Code 39, so printed labels are likely Code 128 or QR.

## What Andrew said

Andrew answered our questions by email on 2026-10-11:

- The team prints its own labels from a template. Most are QR codes, some Code 128.
  "Manta 01" and the like are printed too. The 488 items without a barcode get no labels
  for now. A USB or Bluetooth scanner at the hall types into the search, which works.
- Scanning is mostly for finding an item, and later for checklists.
- An item from a search or a scan starts at a fixed number of hours, not the activity's
  length.
- Km for the trucks, yes. A truck does more on a task than drive from the yard to the
  site, so km are typed, not taken from the mileage report.
- The equipment page listed all 1,136 items, which was too many. It now opens on places
  and categories.
- Leave alone for now: "Same as last" (wait for feedback), who adds equipment (team
  admins), and check-out (stays in D4H).
- Checklists that matter most: truck weekly and truck pre-trip, perhaps filled in by
  members from their own login.
- He added a kit to an activity in South Fraser's D4H, which worked, and set up example
  kits there.

## The equipment page

It opens on two short tables: the places items are in and the categories (D4H's
"kinds"), each with a count of items in service. Picking one lists its items, grouped by
place, with the chain of items holding each one. A search, or a filter other than "In
service", lists items from every place.

## Items members hold

D4H can put an item's location at a member, and the copy keeps it as
`equipment_items.member_id` (#490). A member is a place, as in D4H.

- **What a member holds** is one function,
  [EquipmentItem.held_by/2](../lib/app/model/equipment_item.ex): the items D4H locates
  with the member, and whatever sits inside them, down to 10 levels, as the equipment
  page follows a chain. One recursive query, scoped by the team at every step, so another
  team's item with a matching container id never counts. Retired items are left out. The
  member page, Your membership, and Equipment's member place all read it, so their counts
  always agree (decided 2026-10-23). On production that day 85 items sat inside 16 kits
  members hold, beside 1,683 held directly; one team had 55 inside 6 kits.
- **Equipment, Place** lists the D4H locations, With members, and No location, then each
  member who holds something not retired, by name. It is a combobox, since a team has
  dozens of holders. The URL takes the member's local id, `?place=member-12`, never the
  name, since two members can share one. The section heading names the member ("Sam
  Rivera · 12") and the table drops Where. The browse page's Place table keeps one With
  members row, not one per member. There is no Member filter: it would conflict with
  Place.
- **The member page sidebar**, on every member tab, lists up to 5 items the member holds,
  each linking to its page with its category and barcode, then "All 12 items" to
  Equipment with Place set to them. Shown only when they hold something.
- **Your membership** lists every item, with no cap and no links, so a member knows what
  to bring back.
- In both lists a kit's contents follow it, and an item inside one says "In First aid
  kit 6" in place of its category and barcode, so it reads as part of the kit
  ([EquipmentList.held_rows/1](../lib/app/view_data/equipment_list.ex)).
- With a member picked, the Retired tile reads 0: a retired item isn't with anyone
  (decided 2026-10-23).
- `place=member-<id>` for another team's member, or for a member who holds nothing,
  lists nothing, like an unknown place.
- Still to decide, waiting on Andrew: a badge for a retired member who still holds
  items, a With retired members place, and a Needs attention line on the team home.

## Adding equipment to an activity

The activity page has an Equipment section. "Add equipment" opens a page that builds a
list to send, from:

1. **Same as last incident** (or exercise, or event): the items on the newest earlier
   activity of the same kind that has any, with their minutes.
2. **A search** by name, barcode, or serial. A found item starts at 2 hours, South
   Fraser's most common.
3. **Scanning barcodes** with a phone's camera, which adds each item as it reads it.

Retired and lost items are left out, and so is any item already on the activity. Each
line's hours can change before sending. A vehicle's line takes km instead, typed, and
blank sends none; D4H takes no hours for a vehicle. Sending is a change set of source `equipment`
([ChangeActivityEquipment](../lib/app/operation/change_activity_equipment.ex)), one
`create_equipment_usage` row per item. The applier reads the activity's usages first and
skips an item D4H has on it now, since D4H would count it twice. A published activity
still takes equipment. Removing an item is a `delete_equipment_usage` row. After either,
the activity's usages are read back from D4H.

## The copy

The nightly refresh copies items and usages after groups, and the sync every 10 minutes
watches `equipment` and `equipment-usages` like the other small lists: see
[d4h-sync.md](d4h-sync.md). Items and usages D4H stops listing are deleted. A D4H team
without the equipment module answers 403, so its copy stays empty.

## Scanning barcodes

On a phone (a touch screen, by CSS `pointer: coarse`), "Add equipment" shows "Scan
barcodes" and the equipment page shows "Scan a barcode". Both use the door's
[scanner](../lib/web/components/scanner.ex) with `reader={:barcode}`.

- A scan matches an item's barcode exactly, ignoring case and spaces at the ends, and
  then its serial ([EquipmentItem.find_by_code/2](../lib/app/model/equipment_item.ex)).
  A part of a barcode matches nothing, unlike the search.
- On "Add equipment" the camera keeps going. Each read adds the item at 2 hours, or says
  why not: no item has that barcode, it is already listed or on the
  activity, or it is retired or lost. A tone says which, as at the door.
- On the equipment page one read opens the item's page, even a retired one.
- The reader is [zxing-wasm](https://github.com/Sec-ant/zxing-wasm), vendored as
  `assets/vendor/zxing_reader.js` and `.wasm`. It reads every format ZXing knows,
  1D and 2D, since Andrew asked for any barcode. A page downloads it, about 1 MB, only
  where the scanner is, and the `.wasm` comes from our own assets. ID cards keep jsQR.
- Barcodes come from SAR Duty's copy, so an item added in D4H in the last 10 minutes is
  not found until the next sync.

## Teams on SAR Duty Records

Records serves D4H's equipment endpoints (its `Docs/api.md`), so a Records team gets the
same pages, templates, and "Add equipment". It also has nowhere else to keep its items, so
SAR Duty shows "Add item" on the equipment page and "Change or delete" on an item's
page for Records teams only ([EquipmentItemFormLive](../lib/web/live/equipment_item_form_live.ex),
[SaveEquipmentItem](../lib/app/operation/save_equipment_item.ex)). Each change is an
`:edit` change set row, as for members ([records.md](records.md)).

- The form has a name, type (equipment, vehicle, or supply), status, where it is,
  barcode, serial, and expiry. Kinds are left out for now; an item's type is set
  directly, which only Records takes.
- **Where it is**: the team, one of the places items already sit in, inside another
  item, with a member, or a new place by name. The adapter finds a location with that
  title, ignoring case, or adds it, so a retry never makes a second. An item cannot go
  inside itself or anything inside it; the form leaves those out and Records refuses
  them too.
- Deleting an item takes its usages. Records refuses one with items inside it, and the
  page shows that. Retiring keeps its history.

## Still to come from #271

- Moving an item. Check-out stays in D4H for now.
- Checklists, which live in SAR Duty since D4H's API can't create inspections. Truck
  weekly and truck pre-trip first, perhaps from a member's own login.

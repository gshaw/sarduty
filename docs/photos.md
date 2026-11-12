# Photos

A member's photo is on their ID card, and a checker compares it with the person holding
the card ([member-cards.md](member-cards.md#a-photo-before-a-card)). D4H's web app was
the only way to set one. Photos (#1028) lets a team admin add or change any member's
photo in SAR Duty, on a D4H team and on a Records team. A member adds their own, and a
team admin checks it first (#1029). A team admin asks a member for one by email (#1030).
[Clean up](#clean-up) removes the background and centres the face (#1031), once its
function exists: until then it is off, and a stand-in runs in dev. These are parts 1 to
4 of the photos stack (#1023).

Part 5 starts [activity photos](#activity-photos) (#1032): members add photos to an
exercise or an event they attended, and a team admin accepts them. Part 6 makes the
accepted ones [the team's photos](#the-teams-photos) (#1033): a page for each, stars,
featured photos on the activity's Overview, and Best of the year on Photos. In part 7 a
team admin [asks everyone who attended](#asking-everyone-who-attended). They need a
file store, which production does not have yet, so no team has them today.

## The switch

`teams.photos_enabled`, off on a new team, set on the Features tab through
`SetTeamFeature`. `Team.photos?/1` is the one test. It needs no member logins. With it
off the two pages are not found, and nothing links to them. Coast Range SAR has it on,
so a Try a demo visitor adds their own photo.

## The pages

- **Photos**, `/teams/:subdomain/photos`, one page for everyone
  ([navigation.md](navigation.md#where-a-feature-goes)). A team admin sees every
  counted, current member (`Member.get_all_counted/2`) A to Z, with Members, No photo,
  and Waiting counts that filter. A member sees only [their own](#a-members-own-photo).
  It is the last link of the side navigation's first section and never moves. On a
  team with activity photos, [the team's photos](#the-teams-photos) lead: four more
  counts, for everyone.
- **Add a photo**, `/teams/:subdomain/photos/members/new`, narrow: `?member=<id>` names
  the member, and without it a Member box lists them. Change photo opens the same page.
  A member's photo is under `/photos/members`, which leaves `/photos/:id` for an
  activity's. For a member the page is always their own, whatever the URL says.
- **Check a photo**, `/teams/:subdomain/photos/members/:id`, for team admins: a photo a
  member added, on the certificate review layout.
- The member's ID Card tab has Add a photo for a member with none, and Actions has
  Change photo for a member with one. A Records team's Change member page links to it
  and keeps Remove photo, which only Records can do.

## Who has a photo

Photos never asks the team's records who has one. It reads `members.has_photo`
([CheckMemberPhoto](../lib/app/operation/check_member_photo.ex)), which the night's
refresh checks for a team with ID cards or Photos on, and which turning Photos on checks
at once, behind a spinner on the switch. A member without one shows their initials and
asks for nothing.

A member with one loads `/members/:id/image`, lazily, as the tile scrolls into view. The
route answers `private, max-age=3600`, so a team of 85 calls the team's records at most
once an hour for each browser, not on each visit.
[Web.MemberPhoto](../lib/web/member_photo.ex) builds the path, with
`members.photo_changed_at` as `?v=`: when SAR Duty last set or removed the photo. So a
photo just saved shows at once, past the cached one. A photo changed in D4H's web app
shows within the hour.

## From the phone to the team's records

1. **Pick.** Take a photo and Select a photo open one file input; Take a photo sets
   `capture="user"` first (`PhotoPick` in
   [photo_place.js](../assets/js/photo_place.js)). Images only, up to 10 MB.
2. **Read.** The photo uploads at once.
   [Service.MemberPhoto.prepare/1](../lib/service/member_photo.ex) reads it the way a
   certificate's photo is read (`Service.Image.jpeg/2`): HEIC too, turned the way the
   camera held it, up to 2048 px, with no metadata. The page shows that copy, since a
   browser cannot show every photo a phone takes. It lives in the page's memory until it
   saves: SAR Duty keeps no photo a team admin adds. A page that reconnects starts again
   from the guide.
3. **Place.** The `PhotoPlace` hook moves the copy under the oval: drag, pinch, the
   wheel, Zoom in and Zoom out, Rotate in quarter turns, and the arrow keys. The oval is
   an ellipse centred 50% across and 40% down the square, 42% wide and 52% tall. The hook
   fills hidden fields with the quarter turns and the square: its centre as shares of the
   turned photo's width and height, and its side as a share of the shorter side.
4. **Save.** `MemberPhoto.crop/3`, pure, turns those into pixels and keeps the square
   inside the photo, whatever was sent. `place/3` turns, cuts, and shrinks to 1024 × 1024
   as a JPEG. A square under 1024 px keeps its size.
   [SetMemberPhoto](../lib/app/operation/set_member_photo.ex) sends it as one
   `:set_member_photo` change set row, sets `has_photo`, and refreshes the member's ID
   card.

## A member's own photo

As Brad asks in #1023, a member never changes their own photo without a team admin
(#1029). On a team with member logins and Photos on, a member's Photos shows **Your
photo**: the photo, or "You have no photo yet.", where it stands, and Add a photo or
Change photo. A team admin who is also a member sees the team's views, and their own Add
a photo needs no check.

- **It waits.** [AddOwnPhoto](../lib/app/operation/add_own_photo.ex) makes a
  `member_photos` row, [MemberPhoto](../lib/app/model/member_photo.ex): Waiting, with
  where the member placed it (`turns`, `x`, `y`, `side`). The photo as taken, the 2048 px
  copy from step 2, is a `member_photo_files` row, kept the way a certificate's file
  is. Nothing reaches the team's records, and the ID card keeps its photo: while one
  waits, On your ID card now shows it. A new photo replaces a waiting one.
- **A team admin checks it.** Photos counts them under Waiting, oldest first, and badges
  the member in the grid, New photo waiting. Needs attention has one row, "1 photo
  waiting", that opens Waiting. Only a counted, current member's count
  (`MemberPhoto.get_waiting/2`), so a retiring member's does not. The check page shows
  the square where the member placed it, with step 3's tools, so the team admin fixes
  the framing rather than declining for it. Compare shows the photo as taken and the
  one on the card now.
- **Accept photo** ([AcceptMemberPhoto](../lib/app/operation/accept_member_photo.ex))
  cuts the square as it is placed now and sends it through SetMemberPhoto, as step 4
  does. A refusal leaves the photo waiting and says why (`D4H.error_text/2`).
- **Decline photo** ([DeclineMemberPhoto](../lib/app/operation/decline_member_photo.ex))
  takes one reason from `MemberPhoto.reasons/1` and an optional message, up to 300
  characters. The member's Dashboard says "Your photo was declined: Too dark" under For
  you to do, and Add a photo shows the reason and the message above the examples. Both
  go when they add another, or when a team admin sets their photo
  (`MemberPhoto.declined_for_member/1`). No email goes out.
- **What is kept.** The file is deleted when the photo is accepted or declined. The row
  stays, with who decided, when, and why. While it waits,
  `/photos/members/:id/file` serves it to team admins and to its own member only:
  `?shape=placed` is the square the member placed, and without it the photo as taken.
- **One at a time.** The member adding another, an accept, and a decline take one lock
  for the member (`MemberPhoto.locked/2`), so an accept that is sending never loses the
  photo under it.

## Asking for a photo

A team admin asks a member for a photo, or everyone with no photo at once (#1030). SAR
Duty asks nobody by itself and sends no reminders: a team admin asks again.

- **The page.** Ask for a photo, `/teams/:subdomain/photos/members/ask`, built like Ask
  for a reply: who gets an email, why the rest do not, an optional message of up to 300
  characters, and one send. `?member=<id>` asks that member, from their ID Card tab, their
  tile on Photos, or Actions when they have a photo: for a first photo, a new one, or
  again. Without it, Ask for photos on Photos asks every counted, current member with no
  photo, an email, and no ask still open.
- **Who is asked** is [AskForPhoto.plan/4](../lib/app/operation/ask_for_photo.ex), pure,
  with the reason for each member left out. Sending plans again.
- **The ask** is a `photo_asks` row, [PhotoAsk](../lib/app/model/photo_ask.ex): who
  asked, when, and the message. A member has one open ask. Asking again moves its date
  and sends another email.
- **It closes** when the member's photo is added: by them (AddOwnPhoto), by a team admin
  (SetMemberPhoto), or in the team's records, when the night's check finds a photo where
  there was none (CheckMemberPhoto). A decline does not open it again: the member's
  Dashboard asks for another, and that needs a login, or a team admin asks again.
- **The email** is one `SendPhotoAskWorker` job per ask, queued in the ask's
  transaction, with the ask's id as its args. It comes from SAR Duty, and a reply goes to
  the team admin who asked, under the team's name. A send that fails every try marks the
  ask, and the member's ID Card tab says "The email did not send. Ask again."
- **The link** is `/photos/:token` ([Web.PhotoAskLinks](../lib/web/photo_ask_links.ex)),
  a signed token naming the ask. It opens Add a photo for that member with no login, on
  a team with member logins off too, and nothing else. It works for 30 days from its
  email, and only while the ask is open, so once. After that it says "This link no
  longer works".
- **What people see.** The member's Dashboard has "Add a photo for your ID card" under
  For you to do, with who asked and their message. Their ID Card tab says who asked and
  when, so two team admins do not both ask. Photos shows "Asked Nov 9" under the member
  in place of Add a photo and Ask for a photo.

## Clean up

Clean up removes a photo's background and centres the face (#1031). It will run on a
function in Calgary that does not exist yet, so it is **off in production**, and with it
off no page mentions it: everything above is how Photos works today.
[App.Adapter.CleanUp](../lib/app/adapter/clean_up.ex) is the only module that will know
the function. Its modes, and the variable that turns the stand-in on in dev, are in
[external-services.md](external-services.md#clean-up). `CleanUpPhoto.available?/0` is
the one test pages ask.

While Clean up is available:

- **The guide** takes any background: the plain wall rule becomes "Any background. SAR
  Duty removes it.", the Busy background example goes, and a line under the buttons says
  what Clean up does. The email that asks for a photo says any background works.
- **It runs by itself** on the photo picked, after step 2, in `start_async`, since the
  person waits for it ([jobs.md](jobs.md#job-or-inline)). The page says "Cleaning up…".
  [CleanUpPhoto](../lib/app/operation/clean_up_photo.ex) asks the adapter, which gives
  up after 30 seconds.
- **The result arrives placed.** `Service.MemberPhoto.face_placement/2`, pure, starts the
  square where it puts the face the function found in the oval. Step 3's tools still
  work.
- **The Clean up switch** is on. Off shows the photo as taken, placed by hand. Each side
  starts from its own place, and saving sends the one the switch shows.
- **SAR Duty warns, and never blocks** (`CleanUpPhoto.warnings/2`, pure): more than 1
  face, no face, or a dark photo. With a warning, Take another is the leading button,
  and Add photo still works: a team admin decides, not SAR Duty. Sunglasses and hats get
  no warning, since SAR Duty cannot tell for sure.
- **Dark** is `Service.MemberPhoto.dark?/1`, pure, worked out in the app: the photo as
  taken averages under a fifth of full brightness. It measures the whole photo, never
  the face alone, so it says nothing about skin or hair.
- **When it does not answer**, an error or 30 seconds, a toast says "Clean up did not
  answer. Place your photo yourself." and the page goes on as with Clean up off.
- **A waiting photo keeps both**: `member_photo_files.cleaned_bytes` beside the photo as
  taken, its size on the row, and `member_photos.clean_up`, whether the switch was on,
  which says which photo `x`, `y`, and `side` are on. `?shape=cleaned` serves the
  cleaned-up photo, and `?shape=placed` cuts the square from the one the switch showed.
  A team admin's own Add a photo waits for nobody, so it keeps neither.
- **Check a photo** gets the switch, where the member left it, for a photo with a
  cleaned-up copy. The photo the member placed starts where they placed it, and the other
  from the middle square. Accept photo sends what the switch shows. Busy background is
  not a reason to decline (`MemberPhoto.reasons/1`).

The stand-in cuts the photo to a centred square and reports 1 face, where the oval is,
so dev shows every step but removes no background. A test gives it another answer
through `App.CleanUpStandIn`, to try each warning, an error, and a timeout.

## Sending it

`D4H.set_member_photo/3` branches on the context's host. D4H's form goes only to a D4H
region. Any other host speaks Records' API, so the Records repo's `bin/check-sarduty`,
which runs this adapter against a throwaway Records, still checks the `PUT`.

- **Records:** `PUT /members/:id/image`, as before.
- **D4H:** `POST /documents`, multipart, with `title: "Photo"`,
  `targetResourceType: "Member"`, `targetResourceId`, `profile: "true"`, and the JPEG.
  D4H's spec (7.6.1) says of `profile`: "Whether this document is the profile image".
  **Built from the spec and tested with a stub. Nobody had tried it on a real member
  when it shipped.** Still to learn from a live test: whether it replaces what
  `GET /members/{id}/image` returns, whether the old profile document stays behind,
  whether an Editor's key works, and whether D4H crops or shrinks it.

D4H has no way to remove a photo, so Remove photo stays with Records teams. A refusal
reaches the team admin as `D4H.error_text/2`, and the photo stays on the page to send
again.

## Activity photos

Members take photos at every training and event, and they sit on phones. A member adds
theirs to an activity they attended, with permission to post, and a team admin accepts
them before the team sees them (#1032). They are SAR Duty's own: nothing goes to the
team's records.

- **Off without a file store.** The files are in the
  [file store](external-services.md#file-store), never in SQLite. Production has none
  until storage in Canada exists, so there a team has no tab, no pages, and no counts.
  `AddActivityPhotos.available?/1` is the one test: Photos on, and a store.
- **Which activities.** Exercises and events only, never an incident, and never an
  activity with logged time, such as chores: `Activity.takes_photos?/1`. An exercise
  the team's records turn into an incident stops showing its photos: no tab, no file,
  and no count.
- **Who adds.** `AddActivityPhotos.check/3`, pure: once the activity has started, a
  member who attended (`Attendance.attended/2`), or a team admin. Pages ask
  `may_add?/4`, and the operation asks again.
- **Add photos**, `/teams/:subdomain/activities/:id/photos/new`, narrow
  ([ActivityPhotoFormLive](../lib/web/live/activity_photo_form_live.ex)). The rules show
  above the files, every time. Take a photo and Select photos open one input, as Add a
  photo's do, here with the camera on the back of the phone. Up to 20 photos a send, 25
  MB each. Each uploads when picked and is checked on arrival, so one SAR Duty cannot
  read is refused by name. One caption and one permission to post for the send; the box
  starts unchecked, and unchecked is kept as no. No tools, and no video.
- **On arrival** ([Service.ActivityPhoto](../lib/service/activity_photo.ex)): location
  and camera data go, HEIC becomes JPEG where the server can read it, and three JPEGs are
  kept: the original at its full size, a copy up to 2048 px to show, and one up to 600
  px for tiles. The upload as it came is never kept. Reading 20 photos can pass 30
  seconds, so Add runs in `start_async` ([jobs.md](jobs.md#job-or-inline)): the member
  waits for it, and the page says Adding… until it lands on the tab.
- **The row** is [ActivityPhoto](../lib/app/model/activity_photo.ex): Waiting or
  Accepted, who added it, the send's caption and `may_post`, and `file_token`, a random
  name for its files under the team's prefix, `teams/12/activity-photos/…`.
- **The Photos tab**, `/teams/:subdomain/activities/:id/photos`
  ([ActivityPhotosLive](../lib/web/live/activity_photos_live.ex)), last on an activity
  that takes photos. Accepted photos, the most stars first (#1033), each with who added
  it and when. A team admin gets Waiting over them: every waiting photo as a checked
  tile, then Accept and Delete for the checked ones, and the tab counts them. A team
  admin's own photos wait too. Delete takes the row and its files for good.
- **Who sees a waiting photo**: team admins and the member who added it, nobody else, by
  page and by file. `ActivityPhoto.visible/2` is that rule, for the tab's list and for
  the file route. A member sees their own on the tab, marked Waiting.
- **The file route**, `/teams/:subdomain/photos/:id/file`, with `?size=tile`, `show`, or
  `original`. An accepted photo answers `private, max-age=86400, immutable`, under a
  path that carries when the photo last changed. A waiting one answers `no-store`.
- **Waiting, in two more places.** Needs attention's "3 photos waiting" counts both
  kinds of photo. Photos on Waiting lists the members' photos, then each activity's
  under its title, which opens its Photos tab.
- **Deleting a team deletes its files**: everything under its prefix, after its rows
  (`DeleteTeam`). The copy a delete keeps holds rows only, so a restore leaves the
  photo rows out.

## The team's photos

An accepted photo is the team's (#1033). Everything here is off without a file store,
as activity photos are.

- **One photo**, `/teams/:subdomain/photos/:id`
  ([ActivityPhotoLive](../lib/web/live/activity_photo_live.ex)), for everyone on the
  team: the photo, who added it and when, its activity, its caption, and Posting,
  "Coast Range SAR may post it." or "For the team only." A waiting photo has no page:
  its tile opens its file. `ActivityPhoto.find_accepted!/3` is who opens one, so a
  photo on an activity that became an incident is not found. A photo has no name, so
  search leaves it out (`Web.Search.not_searched/0`).
- **Stars.** Star on the photo's page, for everyone, one each: a row of
  [ActivityPhotoStar](../lib/app/model/activity_photo_star.ex) for the login, and
  starring again takes it back
  ([StarActivityPhoto](../lib/app/operation/star_activity_photo.ex)). The button
  counts them. A tile shows the count, with the star filled when the person looking gave
  one (`ActivityPhoto.put_stars/2`). **Who starred is never shown**, to anyone. A team
  admin viewing as a member sees their own stars, never the member's, and stars nothing.
- **Featured photos.** A team admin features up to 2 on an activity, from the photo's
  page or under its tile on the Photos tab: `activity_photos.featured_at`.
  `FeatureActivityPhoto.check/2`, pure, is the limit, and a third is refused with a
  toast, "2 photos are featured already. Stop featuring one first." The activity's
  Overview shows them beside the map, the first featured first, with "All 12 photos"
  and Add photos for whoever may add. Everyone sees a Featured tag on the tile and the
  page.
- **Photos' views**, the counts that filter, in
  [TeamPhotos](../lib/app/view_data/team_photos.ex). Each tile is the photo, which opens
  its page, its stars, and its activity's name, which opens the activity's Photos tab.
  - **Best of 2026**: the 24 accepted photos with the most stars from activities that
    started that year, in the team's time zone, the most first and the newest photo
    first among equals (`TeamPhotos.best_of/3`, pure). A photo with no star is not in
    it. A Year menu, `?year=`, runs from the first activity with an accepted photo to
    this year.
  - **Activities**: every accepted photo, newest first.
  - **Your stars**: the accepted photos you starred.
  - **Yours**: your [member photo](#a-members-own-photo) and where it stands, then the
    photos you added, waiting ones included and marked. A team admin with no member row
    has the photos their login added.
  - Team admins keep Members, No photo, and Waiting after them.
  - The lists show 50 a page, `?page=`.
- **The view it opens on.** `/photos` with no `?view=` opens Best of this year once the
  team has an accepted photo. Until then it opens as before: Members for a team admin,
  and Yours for a member. Every count's link names its view, so a link from another
  page, such as Needs attention's to Waiting, never depends on it.
- **The buttons.** On the views of members' photos, Ask for photos and Add a photo. On
  the others, Add photos, for whoever may add to some activity. It opens
  `/teams/:subdomain/photos/new` ([PhotoAddLive](../lib/web/live/photo_add_live.ex)),
  narrow, which asks which activity: the ones `AddActivityPhotos.addable/3` lists,
  newest first. For a member, the exercises and events they attended; for a team admin,
  every one that has started. Picking one opens its Add photos page.
- **Team admin actions**, on the photo's page: Edit photo, Feature or Stop featuring,
  Download original, and Delete photo, behind a confirm.
- **Take-downs.** Anyone in a photo can ask a team admin to remove it. Delete photo is
  that ([DeleteActivityPhoto](../lib/app/operation/delete_activity_photo.ex)): the
  files go first, then the row, and its stars with it, for good. Deleting the photos
  that wait on a tab goes through the same operation.
- **Deleting a team** takes the stars with the photos, and a restore leaves both out
  (`DeleteTeam.file_tables/0`).

## Asking everyone who attended

A team admin asks everyone who attended an activity for their photos (#1032, part 7).
Each gets an email whose button opens Add photos for that activity, as them, with no
login. It reuses [Asking for a photo](#asking-for-a-photo)'s page, job, and link.
Nothing asks by itself: a team admin asks, and asks again later.

- **The button.** Ask for photos, beside Add photos on the activity's Photos tab, for
  team admins, once the activity has started (`AskForActivityPhotos.askable?/3`).
  Under the heading, "Asked 10 members on Nov 9, 2026.": how many the last send
  asked, and when (`ActivityPhotoAsk.last/1`, pure).
- **The page**, `/teams/:subdomain/activities/:id/photos/ask`
  ([ActivityPhotoAskLive](../lib/web/live/activity_photo_ask_live.ex)): who gets an
  email, who attended and gets none and why (Added photos, No email, Turned photo asks
  off), an optional message of up to 300 characters, and Ask 10 members.
- **Who is asked** is [AskForActivityPhotos.plan/4](../lib/app/operation/ask_for_activity_photos.ex),
  pure: the team's current members on the activity who attended
  (`Attendance.attended/2`), are not retiring, have added no photo to it, waiting ones
  included, have an email, and take these emails. Asking again later reaches whoever
  still has added none.
- **The ask** is an `activity_photo_asks` row,
  [ActivityPhotoAsk](../lib/app/model/activity_photo_ask.ex): one per member and
  activity, with who asked, when, and the message. Asking again moves its date. It
  never closes.
- **The email** is one `SendPhotoAskWorker` job per ask, as for a member photo, queued in
  the ask's transaction: "Photos from Swiftwater training?", from SAR Duty, with the team
  admin who asked as Reply-To under the team's name. The job sends nothing to a member
  who turned the emails off since, has no email, or may no longer add.
- **The link** is `/photos/activities/:token` (`Web.PhotoAskLinks.activity_path/1`): Add
  photos for that activity as the member asked, with no login, on a team with member
  logins off too. It works for 30 days from its email, as often as the member likes:
  photos turn up on other phones for days. It stops early when the member may no longer
  add (`AskForActivityPhotos.may_add?/2`): the team has no activity photos, the activity
  stopped taking them, or the member left, is retiring, or no longer attended. Photos
  added through it are the member's and wait for a team admin, with no login on the row.
- **Photo asks**, a switch in account settings beside Invitation reminders, for each
  team with activity photos: `members.photo_asks`, the member's own, never from the
  team's records. Off, they get no ask for activity photos. An ask for their member
  photo still comes: the team needs that one.

## Edit photo

Most photos never need cropping. They need to be upright and not muddy. A team admin
fixes an accepted photo on one page (#1032, part 8), and **the original is never
changed**.

- **The page**, `/teams/:subdomain/photos/:id/edit`
  ([ActivityPhotoEditLive](../lib/web/live/activity_photo_edit_live.ex)), for team
  admins, on the certificate review layout a member photo is checked on. A waiting
  photo opens its activity's Photos tab with "Accept the photo first.".
- **The tools.** Rotate left and Rotate right, in quarter turns; Straighten, from −10°
  to 10° in steps of 0.5°; and Clean up, a switch, while
  [Clean up](#clean-up) is available. No crop, and no sliders for light or colour: the
  photo keeps its shape until it is exported.
- **What it shows.** The photo as the team will see it, under a grid to straighten
  against, and the photo as taken beside it. The browser turns and zooms the original
  with CSS, so nothing is made until Save. Clean up is the one change it cannot draw:
  turning the switch on fetches the cleaned-up photo once, in `start_async`
  (`EditActivityPhoto.preview/1`), and the turns apply to it the same way.
- **What is saved** is settings on the row: `turns`, `angle`, and `clean_up`, with
  `edited_by_user` and `edited_at`. Never a new original. One edit, or none: saving
  replaces the last, and there is no history.
  [EditActivityPhoto](../lib/app/operation/edit_activity_photo.ex) makes the copies to
  show and for tiles again from the original.
- **The plan** is `Service.ActivityPhoto.plan/2`, pure: the quarter turns, then the
  angle with the cut that leaves no empty corners (`cut_scale/2`, at the photo's own
  shape), then Clean up. `edit/3` does it at full size, shrinks it to the copy to show,
  and hands that to Clean up, then makes the tile from the result.
- **Clean up** uses the same adapter as member photos, with the kind `:activity`. For
  this kind the function will level the horizon and fix the light and colour. The
  stand-in stretches the light to its full range and the colour a little, so dev shows
  a change. When it does not answer, the photo saves without it, `clean_up` false, and
  the toast says "Clean up did not answer. The photo is saved without it."
- **The photo's page** gets Edit photo first in Actions, and once edited, "Edited by
  Alex Chen, Nov 12, 2026" under the photo, with Revert to original for team admins.
  Revert clears the settings and makes the copies again as they came.
- **Download original** still gives the original, unedited. A page holds the edited
  shape: `ActivityPhoto.shown_size/1` turns the original's size.
- **Files' URLs** carry `updated_at`, and saving always moves it, so no browser keeps the
  old copies.

Export for a post is part 9.

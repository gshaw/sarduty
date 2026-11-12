# Photos

A member's photo is on their ID card, and a checker compares it with the person holding
the card ([member-cards.md](member-cards.md#a-photo-before-a-card)). D4H's web app was
the only way to set one. Photos (#1028) lets a team admin add or change any member's
photo in SAR Duty, on a D4H team and on a Records team. A member adds their own, and a
team admin checks it first (#1029). A team admin asks a member for one by email (#1030).
These are parts 1 to 3 of the photos stack (#1023): Clean up comes next.

## The switch

`teams.photos_enabled`, off on a new team, set on the Features tab through
`SetTeamFeature`. `Team.photos?/1` is the one test. It needs no member logins. With it
off the two pages are not found, and nothing links to them. Coast Range SAR has it on,
so a Try a demo visitor adds their own photo.

## The pages

- **Photos**, `/teams/:subdomain/photos`, one page for everyone
  ([navigation.md](navigation.md#where-a-feature-goes)). A team admin sees every
  counted, current member (`Member.get_all_counted/2`) A to Z, with Members, Waiting,
  and No photo counts that filter. A member sees only [their own](#a-members-own-photo).
  It is the last link of the side navigation's first section and never moves.
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
  takes one reason from `MemberPhoto.reasons/0` and an optional message, up to 300
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

# Photos

A member's photo is on their ID card, and a checker compares it with the person holding
the card ([member-cards.md](member-cards.md#a-photo-before-a-card)). D4H's web app was
the only way to set one. Photos (#1028) lets a team admin add or change any member's
photo in SAR Duty, on a D4H team and on a Records team. It is part 1 of the photos stack
(#1023): members adding their own, asking for one, and Clean up come next.

## The switch

`teams.photos_enabled`, off on a new team, set on the Features tab through
`SetTeamFeature`. `Team.photos?/1` is the one test. It needs no member logins. With it
off the two pages are not found, and nothing links to them. Coast Range SAR has it on,
so a Try a demo visitor adds their own photo.

## The pages

- **Photos**, `/teams/:subdomain/photos`, for team admins: every counted, current member
  (`Member.get_all_counted/2`) A to Z, with Members and No photo counts that filter. It
  is the last link of the side navigation's first section and never moves.
- **Add a photo**, `/teams/:subdomain/photos/members/new`, narrow: `?member=<id>` names
  the member, and without it a Member box lists them. Change photo opens the same page.
  A member's photo is under `/photos/members`, which leaves `/photos/:id` for an
  activity's.
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
   camera held it, up to 2000 px, with no metadata. The page shows that copy, since a
   browser cannot show every photo a phone takes. It lives in the page's memory alone:
   SAR Duty keeps no photo. A page that reconnects starts again from the guide.
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

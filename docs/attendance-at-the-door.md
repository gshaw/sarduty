# Taking attendance at the door

A team admin makes an attendance link for one activity from its **Take attendance** page
([ActivityTakeAttendanceLive](../lib/web/live/activity_take_attendance_live.ex)). Whoever
holds the link opens it on a phone
([AttendanceLinkLive](../lib/web/live/attendance_link_live.ex)). The page shows a short
link, `/s/<code>`, that redirects to `/attendance/<token>`. They scan each member's ID
card as they arrive and leave, or find a member by name. Issue #139 has the design and
the D4H test it rests on.

## What must stay true

- **The token is the only access.** The door's page has no login. Anyone with the link
  can record scans for that one activity and see the team's current member names, and
  nothing else: no contact details, no other activity. The token is 32 random bytes; the
  database keeps its SHA-256 for lookups and the token itself encrypted, so the admin can
  copy the link again.
- **A link is open until it closes.** It opens when it's made, and anyone holding it can
  record arrivals and departures. It closes when a send to D4H goes through for every
  change, when a team admin closes it, or when a new link replaces it. As a backstop, it
  stops working 7 days after the activity ends, so a forgotten link dies. The door's page
  looks the link up again for every scan, so closing it stops an open page at once.
- **The short link dies with it.** Closing or replacing a link deletes its short link,
  and the short link expires on the same backstop.
- **Only this team's cards count.** A card from another team, a cancelled card, or a
  member who has left records nothing. A link to another site is refused, as on the
  verify site, and the scanner never follows it.
- **Scans stay in SAR Duty.** Nothing goes to D4H from the door. Each scan keeps the
  moment it happened and, when the person at the door typed one, the time it stands for.
- **Times come from one pure function**,
  [BuildAttendanceTimes](../lib/app/operation/build_attendance_times.ex). The latest scan
  of each kind wins. Arriving within 30 minutes of the start, early or late, counts as the
  start. Leaving within 30 minutes of the end, early or late, counts as the end. Andrew
  confirmed both sides on #139. A missing scan uses the activity's time and says so.
  Leaving before arriving can't be sent.

## Short links

[ShortLink](../lib/app/model/short_link.ex) is generic: any feature can make one with
`ShortLink.create!/2`. `GET /s/:code`
([ShortLinkController](../lib/web/controllers/short_link_controller.ex)) redirects to the
target, or shows the not-found page for a missing or expired code.

- Codes are 8 lowercase characters from an alphabet without 0, o, 1, l, or i, about 40
  bits. They look nothing like an ID card's uppercase `XXXX-XXXX` code at `/verify/:code`.
- The target is a path, stored encrypted, since it can hold a secret token.
- [Web.ShortLinkLimit](../lib/web/short_link_limit.ex) allows 20 misses per IP every 10
  minutes, so the codes cannot be swept.

## The scanner

The door's page uses the verify site's `QRScanner` hook with `data-continuous`: it keeps
the camera running after a read, waits 1.5 seconds, and ignores the same card until it has
been out of view for 5 seconds.

## Sending to D4H

The **Send to D4H** part of the Take attendance page
([SendAttendanceToD4H](../lib/app/operation/send_attendance_to_d4h.ex)) reads the
activity's attendance from D4H live, plans one change per member, and shows them with
checkboxes. Sending reads D4H again and plans again before it writes. When every change
goes through, it closes the attendance link; a failure leaves it open so the door can
still fix times.

- **A member with a D4H row is always changed, never added.** D4H accepts a second row
  for the same member and counts their hours twice (tested on 2026-10-04, see #139), so
  only a member D4H has no row for gets a `POST`. Writes don't retry: a retried `POST`
  could add someone twice, and a second send plans from what D4H has by then.
- **Signed up and did not arrive means absent**, checked by default. A member already
  attending in D4H with no scan is offered as absent but unchecked, since someone may
  have marked them by hand.
- **A published activity is refused.** D4H's published flag is read live, not from the
  nightly copy, and the page says to unpublish it in D4H first.
- D4H works out the duration from the times. The local copy shows the new attendance
  after the next refresh.

## No-shows

When a send marks a member absent who had signed up (D4H's `REQUESTED`), SAR Duty records
a no-show ([NoShow](../lib/app/model/no_show.ex)). The Take attendance page lists them with
phone and email, and a team admin ticks each one followed up once they know the member is
OK. Sending again doesn't add a second row. A member already attending in D4H whom the
admin marks absent is not a no-show: someone else decided they weren't there.

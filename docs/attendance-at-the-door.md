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
  the mobile numbers of members yet to arrive (decided 2026-10-08, #245), and nothing
  else: no other contact details, no other activity. The token is 32 random bytes; the
  database keeps its SHA-256 for lookups and the token itself encrypted, so the admin can
  copy the link again.
- **A link is open until it closes.** It opens when it's made, and anyone holding it can
  record arrivals and departures. It closes when a send to D4H goes through for every
  change, when a team admin closes it, or when a new link replaces it. As a backstop, it
  stops working 30 days after it's made, so a forgotten link dies. The limit counts from
  the link, not the activity, so a link made for a catch-up after the activity still
  works, and a change to the activity's times in D4H does not move it. The door's page
  looks the link up again for every scan and every Undo, so closing it stops an open
  page at once.
- **The short link dies with it.** Closing or replacing a link deletes its short link,
  and the short link expires on the same backstop.
- **Only this team's cards count.** A card from another team, a cancelled card, or a
  member who has left records nothing. A link to another site is refused, as on the
  verify site, and the scanner never follows it.
- **Scans stay in SAR Duty.** Nothing goes to D4H from the door. Each scan keeps the
  moment it happened and, when the person at the door typed one, the time it stands for.
- **A typed time goes on the activity's date**, not the day it's typed
  ([RecordAttendanceScan.override_at/4](../lib/app/operation/record_attendance_scan.ex)).
  It takes the date that puts it nearest the activity's start-to-end window in the team's
  time zone, so a catch-up the next morning and a time after midnight both land right.
  While a time is set, the door's page says "Recording as 14:30" with a way to clear it.
- **A typed time travels with each record**, not only through a change event. The time
  box and the name search are one form, and a member's button submits it; the scanner
  sends the time box's value with each read. A phone that never sent the change, as on
  Andrew's test (#168), still records the time it shows.
- **Times come from one pure function**,
  [BuildAttendanceTimes](../lib/app/operation/build_attendance_times.ex). The latest scan
  of each kind wins. Arriving within 30 minutes of the start, early or late, counts as the
  start. Leaving within 30 minutes of the end, early or late, counts as the end. Andrew
  confirmed both sides on #139. A missing scan uses the activity's time and says so.
  Leaving before arriving can't be sent.

## Yet to arrive

The door's page and Take attendance list members who signed up, D4H's `ATTENDING`, and
have no scan yet, with Call and Text buttons, so the door can phone them (#245,
[BuildYetToArrive](../lib/app/operation/build_yet_to_arrive.ex)). Any scan counts, so a
member scanned only leaving drops off too. The list reads the copy again on every scan,
so the sync's changes show on the next update.

## Short links

[ShortLink](../lib/app/model/short_link.ex) is generic: any feature can make one with
`ShortLink.create!/2`. `GET /s/:code`
([ShortLinkController](../lib/web/controllers/short_link_controller.ex)) redirects to the
target, or shows the not-found page for a missing or expired code.

- Codes are 8 lowercase characters from an alphabet without 0, o, 1, l, or i, about 40
  bits. They look nothing like an ID card's uppercase `XXXX-XXXX` code on the verify site.
- The target is a path, stored encrypted, since it can hold a secret token.
- [Web.ShortLinkLimit](../lib/web/short_link_limit.ex) allows 20 misses per IP every 10
  minutes, so the codes cannot be swept.

## The scanner

The door's page uses the verify site's `QRScanner` hook with `data-continuous`: it keeps
the camera running after a read, waits 1.5 seconds, and ignores the same card until it has
been out of view for 5 seconds. A good scan's confirmation shows for 3 seconds, then
clears for the next member.

Each scan sounds and shows its result, since a read is too fast to notice otherwise
(#169). The confirmation is a big banner: green for arrived, blue for left, red for an
error. The tones come from [scan_sound.js](../assets/js/scan_sound.js), made with Web
Audio: rising for arrived, falling for left, a low double buzz for an error. The
LiveView pushes a `scan-sound` event, and the verify site uses the same tones for a scan
or a typed code: rising for an active member, the buzz for anything else. A browser
plays sound only after a tap, so any tap on the page turns it on. Safari's camera prompt
on a first scan pauses the audio, so each tone wakes it first; before that, the first
check on an iPhone was silent (2026-10-06). The **Sound** switch under the scan button is
remembered on the phone. On an iPhone the page sets its audio session to playback, so
the silent switch doesn't mute it (Safari 17 and later). Sound stopped for good after
switching apps (2026-10-06): an iPhone pauses a background page's audio and often never
resumes it. The page now drops its audio when hidden and starts fresh on the next tap,
so after switching back, the first scan sounds only once someone has tapped the page.
The camera stops when the page is hidden, so that tap is the one on the scan button.

The hook keeps its scanning flag on the `[data-scan-state]` element inside it, not on the
`phx-update="ignore"` container. LiveView still patches the container's data attributes,
so a flag there was wiped by the render after each scan. The page went back to "Scan ID
cards" while the camera kept running.

## Sending to D4H

The **Send to D4H** part of the Take attendance page
([SendAttendanceToD4H](../lib/app/operation/send_attendance_to_d4h.ex)) reads the
activity's attendance from D4H live, plans one change per member, and shows them with
checkboxes. Sending reads D4H again, plans again, and sends the kept changes as a
[change set](change-sets.md). When every change
goes through, it closes the attendance link; a failure leaves it open so the door can
still fix times.

- **A member with a D4H row is always changed, never added.** D4H accepts a second row
  for the same member and counts their hours twice (tested on 2026-10-04, see #139), so
  only a member D4H has no row for gets a `POST`. Writes don't retry: a retried `POST`
  could add someone twice, and a second send plans from what D4H has by then.
- **Signed up and did not arrive means absent**, checked by default, with a note. Signed
  up is D4H's `ATTENDING`, which also means someone marked the member there by hand, so
  the admin unchecks anyone who came. With no scans at all the door wasn't used, and
  nothing is offered.
  `REQUESTED` only means invited: D4H gives every invited member that row until they
  reply, so a requested row with no scan is left alone.
- **A published activity is refused.** D4H's published flag is read live, not from the
  copy, and the page says to unpublish it in D4H first.
- **A 400 or 404 says the activity may be gone.** D4H answers that way when the activity
  or a row was deleted or changed, so the page says so before D4H's own text. An
  activity the sync has marked deleted (#160) is refused before D4H is read.
- D4H works out the duration from the times. The local copy shows the new attendance
  after the next sync, within 10 minutes.

## No-shows

When a send marks a member absent who had signed up (D4H's `ATTENDING`), SAR Duty
records a no-show ([NoShow](../lib/app/model/no_show.ex)). The Take attendance page lists
them with phone and email, and a team admin ticks each one followed up once they know the
member is OK. Sending again doesn't add a second row.

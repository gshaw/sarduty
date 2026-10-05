# Taking attendance at the door

A team admin makes an attendance link for one activity from its **Take attendance** page
([ActivityTakeAttendanceLive](../lib/web/live/activity_take_attendance_live.ex)). Whoever
holds the link opens it on a phone at `/attendance/<token>`
([AttendanceLinkLive](../lib/web/live/attendance_link_live.ex)). They scan each member's ID
card as they arrive and leave, or find a member by name. Issue #139 has the design and
the D4H test it rests on.

## What must stay true

- **The token is the only access.** The door's page has no login. Anyone with the link
  can record scans for that one activity and see the team's current member names, and
  nothing else: no contact details, no other activity. The token is 32 random bytes; the
  database keeps its SHA-256 for lookups and the token itself encrypted, so the admin can
  copy the link again.
- **A link closes.** Making a new link closes the old ones, a team admin can close it, and
  it stops a day after the activity ends. The door's page looks the link up again for
  every scan, so closing it stops an open page at once.
- **Only this team's cards count.** A card from another team, a cancelled card, or a
  member who has left records nothing. A link to another site is refused, as on the
  verify site, and the scanner never follows it.
- **Scans stay in SAR Duty.** Nothing goes to D4H from the door. Each scan keeps the
  moment it happened and, when the person at the door typed one, the time it stands for.
- **Times come from one pure function**,
  [BuildAttendanceTimes](../lib/app/operation/build_attendance_times.ex). The latest scan
  of each kind wins. Arriving up to 30 minutes before the start counts as the start, and
  leaving up to 30 minutes after the end counts as the end. A missing scan uses the
  activity's time and says so. Leaving before arriving can't be sent.

## The scanner

The door's page uses the verify site's `QRScanner` hook with `data-continuous`: it keeps
the camera running after a read, waits 1.5 seconds, and ignores the same card until it has
been out of view for 5 seconds.

# Taking attendance

Anyone who logs in to the team takes attendance for an activity from its **Take
attendance** page, `/teams/:subdomain/activities/:id/take-attendance`
([ActivityTakeAttendanceLive](../lib/web/live/activity_take_attendance_live.ex)), on a
phone, an iPad at the hall, or a laptop. They scan each member's ID card as they arrive
and leave, or find a member by name. A team admin reviews and sends the attendance to
D4H from the activity's **Attendance** page
([ActivityAttendanceLive](../lib/web/live/activity_attendance_live.ex)). Issue #139 has
the first design and the D4H test it rests on; #475 replaced its links with a login.

## The team's page

`/teams/:subdomain/take-attendance`
([TakeAttendanceLive](../lib/web/live/take_attendance_live.ex)) is for an iPad at the
hall. Under a line saying what it's for, **Now** lists the activities taking attendance
now (`Activity.taking_attendance_now/2`), and **Coming up** the next 5 whose window opens
later, within 14 days (`Activity.taking_attendance_later/2`). Every row opens that
activity's scanner, which says when a member can start. It never opens a scanner by
itself: with one activity on, it jumped straight there, so "Other activities now" and a
printed QR code landed somewhere that didn't say what it was (2026-10-25). It looks again
each minute, so an activity moves to Now when its window opens. A team adds it to the
iPad's Home Screen or prints a QR code of its address for the hall or command post. The
address can't move ([urls.md](urls.md)). The scanner links back to it, Other activities
now, while another activity is taking attendance: one that overlaps, or tonight's when
Safari kept last week's scanner open. Take attendance is in the side navigation for
members and team admins, always.

Logged out, it goes to the login page as every team page does, and logging in comes back
to it. When the page to come back to is a Take attendance page, the login pages say "Log
in to take attendance.", and Remember me's hint says to leave it unticked on a shared
device and log out when done. The "Log in to see this page." toast is left off there,
since toasts stay until tapped and it would cover that line.

## What must stay true

- **A login, not a link.** There are no attendance links and no page without a login. A
  leaked link showed member names and the phone numbers of members yet to arrive to
  anyone (#475). A login names the person and ends when they leave D4H. Old
  `/attendance/:token` and `/s/:code` links get the not-found page.
- **Who takes attendance is one function**,
  [Activity.take_attendance?/3](../lib/app/model/activity.ex). Team admins take it at any
  time, to catch up from a paper list the next morning. On teams with member logins,
  members take it from 2 hours before the activity starts until 2 hours after it ends;
  outside that the page says when it opens, or that it closed and to ask a team admin.
  Nobody takes it for a deleted activity. The same function decides whether Take
  attendance shows on the activity panel and whether a scan is saved. The page checks
  again on every scan and Undo, and once a minute, so a page left open opens with the
  window and stops when it closes.
- **Needs attention says there's attendance to send.** A team admin no longer makes a
  link, so nothing else tells them members have scanned.
  [TeamDashboardViewData.attendance_to_send/2](../lib/app/view_data/team_dashboard_view_data.ex)
  lists activities not deleted and not published, finished in the last 30 days, with a
  scan since their `attendance_sent_at`. A published activity's attendance is final:
  whoever published it checked it in D4H, and D4H refuses a send. A review sets
  `attendance_sent_at` when it has nothing to send or D4H says published, and a send when
  every change went through and none waits on fixed times
  ([Activity.mark_attendance_sent/2](../lib/app/model/activity.ex)); a change left
  unchecked is the team admin's choice, and with all of them unchecked, Send reads "Send
  no changes". It takes the review's time, not the send's, so a
  scan in between still waits. One activity is named in the item and opens its
  Attendance page; several are counted, and the oldest opens. The 30 days keep a scan
  nobody means to send from waiting forever.
- **Each scan records who took it**: `recorded_by_user_id`, and `recorded_by_member_id`
  when that user is one of the team's members. The Attendance page's **Recorded by**
  column names them, or a user's email for someone who isn't a member. Scans from before
  #475 name nobody.
- **Members see names only.** Yet to arrive on a member's page has no phone numbers and
  no Call or Text, since members never see contact details (#406). Team admins keep them.
- **A team admin viewing as a member saves nothing**, as replies don't.
- **Only this team's cards count.** A card from another team, a cancelled card, or a
  retired member records nothing. A link to another site is refused, as on the
  verify site, and the scanner never follows it.
- **Scans stay in SAR Duty.** Nothing goes to D4H until a team admin sends it. Each scan
  keeps the moment it happened and, when the person taking attendance typed one, the time
  it stands for.
- **A typed time goes on the activity's date**, not the day it's typed
  ([RecordAttendanceScan.override_at/4](../lib/app/operation/record_attendance_scan.ex)).
  It takes the date that puts it nearest the activity's start-to-end window in the team's
  time zone, so a catch-up the next morning and a time after midnight both land right.
  While a time is set, the page says "Recording as 14:30" with a way to clear it.
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

Take attendance and the Attendance page list members who signed up, D4H's `ATTENDING`,
and have no scan yet (#245, [BuildYetToArrive](../lib/app/operation/build_yet_to_arrive.ex)).
Team admins get Call and Text buttons, so they can phone them; members get names. Any scan counts, so a
member scanned only leaving drops off too. The list reads the copy again on every scan,
so the sync's changes show on the next update.

## The scanner

Take attendance uses the verify site's `QRScanner` hook with `data-continuous`: it keeps
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

**Switch camera**, beside Stop scanning on a device with more than one camera, swaps the
back and front cameras (#248). It is for an iPad set up at the door facing the members,
who hold their card up to its front camera. The choice is remembered on the device, so a
kiosk keeps it after a reload, and the front camera's picture is mirrored. The verify
site and the equipment pages share the switch, since they share the hook.

The hook keeps its scanning flag on the `[data-scan-state]` element inside it, not on the
`phx-update="ignore"` container. LiveView still patches the container's data attributes,
so a flag there was wiped by the render after each scan. The page went back to "Scan ID
cards" while the camera kept running.

## A plug-in barcode scanner

A USB or Bluetooth barcode scanner works on a laptop or an iPad (#484). It acts as a
keyboard: it types what the QR code holds, the card's verify link, and presses Enter.
It types into **Find a member by name**. On Enter, the box records a card when its text
is a link or a card's code with a dash or a digit (`card_entry?/1`), and searches names
otherwise. While a link is still being typed the box shows no "no member" line.

The `ScannerInput` hook ([scanner_input.js](../assets/js/scanner_input.js)) handles the
cursor. On a laptop (`pointer: fine`) the box takes it when the page opens and after
Arriving or Leaving. After a card it empties the box itself, since LiveView leaves a
focused input's value alone. On an iPad someone taps the box once: iOS ignores focus a
page sets without a tap, and the cursor would open the on-screen keyboard. A paired
Bluetooth scanner counts as a keyboard, so iOS hides the on-screen one; typing a name
then needs the keyboard button at the bottom of the screen.

A team needs a 2D imager that reads phone screens. A 1D laser scanner can't read QR
codes. Wallet turns the brightness up when it shows a pass.

## Sending to D4H

The **Send attendance** part of the Attendance page
([SendAttendanceToD4H](../lib/app/operation/send_attendance_to_d4h.ex)) reads the
activity's attendance from D4H live, plans one change per member, and shows them with
checkboxes. Sending reads D4H again, plans again, and sends the kept changes as a
[change set](change-sets.md). Scans taken after a send show up in the next review.

- **A member with a D4H row is always changed, never added.** D4H accepts a second row
  for the same member and counts their hours twice (tested on 2026-10-04, see #139), so
  only a member D4H has no row for gets a `POST`. Writes don't retry: a retried `POST`
  could add someone twice, and a second send plans from what D4H has by then.
- **Signed up and did not arrive means absent**, checked by default, with a note. Signed
  up is D4H's `ATTENDING`, which also means someone marked the member there by hand, so
  the admin unchecks anyone who came. With no scans at all Take attendance wasn't used, and
  nothing is offered.
  `REQUESTED` only means invited: D4H gives every invited member that row until they
  reply, so a requested row with no scan is left alone.
- **A published activity is refused.** D4H's published flag is read live, not from the
  copy, and the page says to unpublish it with Change activity first.
- **A 400 or 404 says the activity may be gone.** D4H answers that way when the activity
  or a row was deleted or changed, so the page says so before D4H's own text. An
  activity the sync has marked deleted (#160) is refused before D4H is read.
- D4H works out the duration from the times. The local copy shows the new attendance
  after the next sync, within 10 minutes.

## No-shows

When a send marks a member absent who had signed up (D4H's `ATTENDING`), SAR Duty
records a no-show ([NoShow](../lib/app/model/no_show.ex)). The Attendance page lists
them with phone and email, and a team admin ticks each one followed up once they know the
member is OK. Sending again doesn't add a second row.

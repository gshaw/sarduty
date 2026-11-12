# Member ID cards

A team manager issues a member an ID card from the member's **ID Card** tab, once a SAR
Duty admin has turned ID cards on for the team on its admin page, `/admin/teams/:id`, or its organization
admins have, on its page in the organization (#512). A team pilots cards with a few
members, then turns on **Every member gets a card** and every member gets one
([Every member gets a card](#every-member-gets-a-card)). The member gets an email with a
link to the card's page, where they add it to Wallet
([Issuing and emailing](#issuing-and-emailing), [The card's page](#the-cards-page)). A
member sees the
card on their own page ([members.md](members.md)). Anyone can
check a card by scanning its QR code with a phone's camera, which opens its page on the
verify site, `verify.sarduty.com/K7Q4M-2XA9H`
([VerifyLive](../lib/web/live/verify_live.ex)), or by typing the code printed under it
at `verify.sarduty.com`. Issue #63 has the design and the plan. A team in a parent
organization gets its branding: see [organizations.md](organizations.md).

## What must stay true

- **Only teams a SAR Duty admin checked issue cards.** A card verifies on SAR Duty's own
  verify site, and anyone can sign up a team on SAR Duty Records, so a SAR Duty admin
  checks a team when turning on its cards, or when adding it to an organization. That
  organization's admins can then turn its cards on or off, and nobody else
  ([SetTeamIdCards](../lib/app/operation/set_team_id_cards.ex) checks who acts). Each
  change emails the team's team admins.
  [IssueMemberCard](../lib/app/operation/issue_member_card.ex) refuses a team without it,
  and every path that issues goes through it. Teams that signed up before the switch have
  it on; a new team starts with it off. Turning it off cancels every live card on the
  team and tells phones, so a team that lost it can't keep showing valid cards.

- **The real check is the server's answer and the photo.** A pass is easy to fake with
  any pass-maker app. What can't be faked is sarduty.com saying the code is active and
  showing the member's face, so the result shows the photo large and tells the checker
  to look at the address bar.
- **The QR opens the card's page, and only the code is printed under it.** It holds
  `HTTPS://VERIFY.SARDUTY.COM/K7Q4M-2XA9H`
  ([MemberCard.qr_url/2](../lib/app/model/member_card.ex)), in capitals because a QR code
  packs capitals, digits, and `:/.-` into fewer squares. That's 38 characters, which fits
  the size-2 QR code. A 12-character code would not.
- **The verify site serves only the check.** The router matches it by its `verify.`
  host ([Web.VerifyHost](../lib/web/verify_host.ex)). There's no login there, and the
  app's session cookie never reaches it, since that cookie is host-only. Other paths go to
  the app; a one-segment path reads as a code. The app has no `/verify` (#153), and the
  websocket's `check_origin` lists both hosts.
- **Scanning from the verify site is the careful check.** The page's scanner never
  follows a link. It takes the code out of a card's link, accepts a bare code, and flags
  a link to anywhere else as forged.
- **Codes are random.** They come from `:crypto`, 10 characters from a 30-character
  alphabet ([MemberCard](../lib/app/model/member_card.ex)), printed 5-5. Never derive
  one from the D4H member number or the local id: a guessable code would let anyone walk
  the roster.
- **Only 10-character codes count.** Codes were 8 characters until #969. Each live card
  then got a 10-character code
  ([LengthenCardCodes](../lib/app/operation/lengthen_card_codes.ex)), keeping its row,
  serial, and token, so its passes changed in place at the push that followed. An old
  code matches no card, and a cancelled card from before then keeps its 8 characters,
  which nothing looks up.
- **Misses are capped per IP.** 20 codes that match no card in 10 minutes, on the page,
  the photo and banner routes, or the JSON check, and that IP gets "Too many tries" with
  no lookup ([Web.VerifyLimit](../lib/web/verify_limit.ex)). Real codes never count, so
  checking a crowd of cards at a callout can't trip it. Nor does input that can't be a
  code, since it can't guess one: at a command post everyone shares one IP, and an app
  that sends every barcode it reads would otherwise lock the post out (#299). The counts live in memory (Hammer's ETS
  backend), which is enough on one machine and resets on deploy. The IP is Fly's
  `Fly-Client-IP`, read on the HTTP request and carried into the LiveView's session,
  since a websocket can't see that header.
- **Misses across the site raise an alarm, never a block.** 500 misses in an hour from
  any mix of IPs records a Verify alarm event and tells Honeybadger. A site-wide block
  would refuse real cards too, so anyone could stop every card check at a callout with
  junk codes. Slowing misses doesn't work either: a guesser drops any answer that takes
  long, and a fast answer gives the hit away. While the alarm is up, a real card found
  from an IP that has missed this window is recorded as Card found during alarm, with
  the card's id. A published document's ID counts the same way (#970), its hit recorded
  with the document's id.
- **A cancelled card shows nothing about the member.** The verify site says it was cancelled,
  and its photo route 404s. Cards are cancelled only by Cancel ID card (#964, #1012) and
  by the team's ID cards switch turning off.
- **A card that is not active shows no photo.** The page gives the name, the team, and
  "Not active", and the photo and banner routes 404, as for a cancelled card (#176). "Not
  active" is the whole answer a checker needs. A retired member's page says when they
  left; a retiring member's says no more.
- **One live card per member.** Issue makes a card only for a member with none, and a
  code is never reused.
- **Status comes from the local copy of D4H**, so it can be 10 minutes behind, or a day
  for a change D4H doesn't mark ([d4h-sync.md](d4h-sync.md#where-the-copy-drifts)). The result says
  when the team last refreshed.

## When the verify alarm goes off

At about 3,000 misses a day per IP, 1,000 IPs would take about 56 years to find a
random card among 10,000, so there's time to look. With 8-character codes it was 3
weeks (#969).

1. Check it's guessing, in Adminland's Events: many IPs sending codes that never repeat.
   A few IPs with near-misses is a broken scanner or an app sending stale codes.
2. Filter Events by Card found during alarm. Each is a card whose name, team, and
   standing a guesser may have seen. Cancel it, issue a new one, and tell the team's
   admins.
3. If it goes on, block the ranges at the edge. Last resort, a browser challenge on the
   verify page, which breaks apps on the JSON check until they get keys.

Don't replace every card for this: a guess gets one name and photo. The public side of
this is the Guessing codes section of `/agents/id-cards`, which gives the per-IP limit
but not the alarm's count.

## The check as JSON

`verify.sarduty.com/api/v1/cards/K7Q4M-2XA9H`
([CardApiController](../lib/web/controllers/card_api_controller.ex)) answers the same
check for apps that sign members in by scanning their card, SAR Command Assist first
(#299, [sar-command-assist.md](sar-command-assist.md)).
[How to check an ID card](../lib/web/card_api_doc.ex), at `/agents/id-cards`, is its
public documentation. The page and the JSON share
[CheckMemberCard](../lib/app/operation/check_member_card.ex), so they never disagree.

- **It says what the page says**, plus where an active member's records live: `service`
  (`d4h` or `sar_duty_records`, the API's own names, not `D4H.service/1`'s atoms), the
  API's URL, and the team and member IDs there. Those open nothing without the team's own
  access key, and they let an app match a card to a member it already has, where a team's
  own ID number repeats across teams.
- **Same rules as the page.** A cancelled card gives its status only; a retired member's
  gives the name, the team, and when they retired, with no photo and no IDs (#176). Misses
  count toward the same per-IP limit, and a limited IP gets `429` with `Retry-After`.
- **Apps hold v1.** Add fields freely; renaming or removing one, or changing what a status
  means, is `/api/v2` beside it. The doc tells apps to ignore fields they don't know.
- **No key, no CORS header.** It reads only what a card's holder already shows anyone.
  Desktop and phone apps don't need CORS; add it only when a web app asks.

## In reports

Team admins on a team with ID cards can add three member fields to a report (Andrew,
2026-11-06): `id_card`, the code as printed; `id_card_link`, the card's page on the verify
site, in lowercase (only the QR's copy is in capitals, to keep it small); and
`id_card_issued`. Each reads the member's live card from `MemberCard.live_query/1`, and is
blank with none, so a cancelled card never shows. It's for printing cards and loading
codes into another app, such as SCA. A copied code goes stale when a card is replaced, and
an app that matches it offline skips the Active check. There is no expiry field: Valid
until is the team's, not the card's ([Valid until](#valid-until)).

`has_photo` ("Photo") sits with them (#1012), and the built-in report
`members-without-a-photo` lists counted, current members without one, with their card's
code, so a card already out with the placeholder shows too. Reports lists it only for a
team with ID cards on (`BuiltIn.runs?/2`).

## A photo before a card

A member gets an ID card only once their team's records have a photo of them (#1012). A
checker compares the photo on the verify page, so a card with the placeholder can't be
matched to the person holding the phone.

- **`members.has_photo`** says whether the team's records had a photo at the last check.
  [CheckMemberPhoto](../lib/app/operation/check_member_photo.ex) decides it with one
  `GET /members/:id/image`: a 200 is a photo, a 204 or 404 none. For a member with no
  photo D4H answers 204 with no body, never a stock avatar (checked on South Fraser's 85
  current members, 2026-11-11: 66 photos, all different, and 19 204s), and Records 404.
  Any other answer, such as a rate limit or an outage, or none at all, keeps what was
  stored.
- **Nightly**, after a team's full refresh and before Every member gets a card, it checks
  each counted, current member on a team with ID cards or Photos on, card holders too, so
  the report is right for everyone. One request per member, outside any transaction. New
  photos are found then, not on the 10-minute sync. A card holder with a photo where
  there was none gets their card refreshed, all of them in one push and one Google update
  (`RefreshMemberCard.resend_cards/2`), so a card that went out with the placeholder gets
  the photo on the phones that night. A photo swapped for another needs Refresh ID card:
  seeing a change would mean downloading and comparing every photo.
- **Issue** checks live first, outside the transaction, so a photo added a minute ago
  counts. `IssueMemberCard` refuses with `:no_photo`, one rule for Issue and the switch
  (`IssueMemberCard.refusal/2`). The toast: "Riley Okafor has no photo. Add one, then try
  again."
- **Stored, not checked per member**, because the switch makes every card in one
  transaction and the Features tab counts them as it loads. A request per member there
  would hold the write lock or slow the page.
- **Cards already out stay**, with or without a photo, and so does a card whose photo is
  later removed, until a team admin selects Cancel ID card. Change member already warns.
  Nothing checks what a photo shows: a photo that is not the person fails at the verify
  page, the same as none.
- **A photo saved in SAR Duty** (Add a photo, #1028, [photos.md](photos.md)):
  SetMemberPhoto sets `has_photo` itself, with no download, refreshes the card, and runs
  Every member gets a card, so the switch's card goes out the moment a first photo is
  saved. With Photos on, a member with no photo gets Add a photo on the ID Card tab in
  Issue ID card's place.
- **Try a demo** skips the nightly refresh, so `BuildDemoTeam` sets `has_photo` from the
  cast: true for each person with the sample photo, false for the visitor. The visitor's
  prebuilt card works; a new one after Cancel asks for a photo, which Add a photo adds.
- No words name D4H or Records ("has no photo"), so one sentence fits both kinds of team.

## Refresh ID card

**Refresh ID card** on the ID Card tab puts a fixed photo, name, or standing on the
member's phones within a minute, for an active card while Wallet is set up (#1012). It
needs no confirm and sends no email: it changes nothing but the phones' copy.
[RefreshMemberCard](../lib/app/operation/refresh_member_card.ex) checks the photo, marks
the Apple pass changed (`touch_pass_updated!`) and pushes to every phone holding it,
sends the Google object again with a new photo URL, and queues the team's sync, so a fix
just made reaches the card in the same minute. The toast: "Cameron Ruiz's ID card
refreshed. Phones that hold it get it within a minute." The team admin checks the card
picture on the tab; the member checks Wallet.

Where a new photo shows, for a photo that replaces another. A first photo, where the
card had the placeholder, reaches Wallet that night too ([nightly](#a-photo-before-a-card)).

| Where                                    | Without Refresh ID card                                           | With it         |
| ---------------------------------------- | ----------------------------------------------------------------- | --------------- |
| The ID Card tab, the card's page, verify | At once: drawn from the team's records                            | At once         |
| Apple Wallet                             | With the monthly expiry update: the fingerprint is pass.json only | Within a minute |
| Google Wallet                            | With the monthly expiry update, which moves the photo URL         | Within a minute |

## Sample cards

`verify.sarduty.com/samples` ([VerifySamplesLive](../lib/web/live/verify_samples_live.ex))
has a QR code for each answer the check gives, for demos and docs (#854). The cards are
Coast Range SAR's, the made-up team ([App.CoastRange](../lib/app/coast_range.ex)), and
their codes change only when the code format does (#969): `SAMPX-ACTVX` (Cameron Ruiz,
active), `SAMPX-RTRDX` (Robin Tse, retired), `SAMPX-CNCDX` (cancelled), and
`SAMPX-NCRDX`, which no card has. A fifth QR code links to `verify.sarduty.example`, a
domain nobody can register, for "Not a SAR Duty card".

- **A sample is looked up in App.SampleRepo only**, never the real database, and every
  sample result opens with a "Sample card" band saying never to accept it as ID. Without
  it, anyone could print `SAMPX-ACTVX` on a fake card and get a green Active member.
- **No real code starts with `SAMP`.** `MemberCard.generate_code/0` rolls again.
- **Samples never count toward the miss limit**, so a demo of "No card has this code"
  never locks anyone out. The active sample's photo is the placeholder, since Coast Range
  SAR has no D4H, and its logo is SAR Duty's.

## Apple Wallet

A member adds their card on the card's page ([The card's page](#the-cards-page)). Its
email links there, and so do Show ID card on Your membership, `/teams/:subdomain/me`,
and Add ID card to Wallet on the Dashboard's to-do. The page builds the pass when they
tap, once Apple Wallet is set up (see [external-services.md](external-services.md)). The
email carries no pass (#952). The ID Card tab has no Wallet buttons: they would put the
member's card on the team admin's phone.

Passes update. Each pass carries a `webServiceURL` of `/wallet` and the card's
`authentication_token`. Wallet registers the phone with
[WalletController](../lib/web/controllers/wallet_controller.ex), and
[PushPassUpdates](../lib/app/operation/push_pass_updates.ex) pushes through APNs:

- **After every team refresh** it rebuilds each registered card's pass and pushes only
  when its fingerprint changed. The fingerprint leaves out the "last checked" date, or
  every pass would buzz every day.
- **When a pass is built** for a download or a phone, and its fingerprint
  changed, it pushes too. Building records the fingerprint, so the next refresh would
  otherwise see nothing new and the phones would keep the old pass.
- **On replace, or the ID cards switch turning off,** a job per card
  (`UpdateCancelledCardWorker`, queued with the cancel) pushes, and Wallet fetches a
  voided pass that says "Cancelled".
- A phone that APNs says dropped the pass, or whose token is bad, is deleted.
- **A member keeps one Wallet serial number** across replacements, so a replacement pass
  lands on the existing pass instead of beside it. Each card has its own token, and a
  phone's token picks which card it gets, so a lost phone still holding the old token
  only ever gets the old card, voided. Cards made before this keep `member-card-<id>`.
- **A replacement isn't on a phone until a phone fetches it.** Wallet doesn't register
  again when a replacement lands (#70), so the serial's registrations belong to whichever
  card each phone holds. A card counts the devices that registered it. With none, it
  counts the serial's devices once one fetched its pass with its own token, and none
  before that, while they hold the cancelled card (`PassRegistration.holding/2`, #952).
  So a lost phone isn't counted once the new phone registers the replacement. Pushes
  still go to every phone with the serial.
- A pass made before updates existed has no token, so it never updates. Its card gets a
  token the next time its pass is built.
- Pushes reach phones from dev too: a cancelled card's notice and the card page's
  nudges arrived on a real iPhone from the dev server (2026-11-07).

The ID Card tab's Wallet row shows how many devices hold the pass (an iPhone and a paired
Apple Watch count as 2), and whether the member saved it to Google Wallet
(`in_wallet_at`). A phone's fetch broadcasts on PubSub, so the tab ticks over without a
reload. It no longer shows when a phone last downloaded the pass (#1012): Google Wallet
has nothing like it, and it added little. `pass_fetched_at` is still kept, for
`PassRegistration.holding/2`. Under the buttons it says how the card reaches the member:
from Your membership on a team with member logins, otherwise by email.

A failed push logs "APNs pass push failed". To push a pass now, select Refresh ID card
([Refresh ID card](#refresh-id-card)).

Wallet has no CSS and shows images only as PNG, so
[LoadImage](../lib/app/operation/load_image.ex) shapes them with
[Service.Image](../lib/service/image.ex): the D4H photo cropped to a centered square, and
the team's saved logo converted to PNG, since D4H may send a JPEG. A missing or broken
image falls back to the placeholder photo or SAR Duty's logo. The member page, the team
dashboard, and tax credit letters use the same images, so what a manager sees is what
goes on the pass.

## Google Wallet

The card's page's **Add to Google Wallet** sends the card's pass to Google and opens
Google's save page ([The card's page](#the-cards-page)). The save link is a JWT that names
the pass and nothing else; Google holds the pass itself.

Google keeps the pass, so there's no phone to push to.
[UpdateGooglePasses](../lib/app/operation/update_google_passes.ex) sends Google a card's
pass again, and every saved copy changes:

- **After every team refresh**, for cards whose pass changed. The fingerprint leaves out
  the "last checked" date, as for Apple. A card with no `google_pass_fingerprint` has no
  pass at Google and is skipped.
- **On replace, or the switch turning off,** the same job sends the old pass as `EXPIRED`, with no QR code
  or photo, and Wallet moves it to "Expired passes". A refusal is tried again: the
  refresh only sends live cards, so nothing else would.
- **A replacement is a new pass.** Each card has its own Wallet object, because Google
  has no per-phone token to say which card a phone holds. The member adds the new one.

**In Wallet** (#389): the team's Dashboard lists "Add your ID card to Wallet" under a
member's For you to do (#406) until SAR Duty knows the card is in one
(`MemberCard.in_wallet?/1`). Your membership's Show ID card stays: it opens the card's
page, where a member adds it again on a new phone (#952), saves it, or prints it (#973). Apple Wallet registers the
phone, for the serial. Google
posts a signed message to `/wallet/google` when the member saves or deletes the pass: the
class's `callbackOptions`, production only, since Google can't reach a dev server.
[GoogleWallet.Callback](../lib/app/adapter/google_wallet/callback.ex) checks it with
Google's `ECv2SigningOnly` protocol: a root key from `pay.google.com/gp/m/issuer/keys`
signs an intermediate key, which signs the message for SAR Duty's issuer. A save sets the
card's `in_wallet_at` and a delete clears it
([RecordGoogleWalletEvent](../lib/app/operation/record_google_wallet_event.ex)). A Google
replacement is a new pass, so the mark is per card. Google may retry or repeat a message,
and both are safe to take twice. Another host's class (dev shares the issuer) and unknown
cards get a 200 and change nothing; a bad signature gets a 400.

Google loads images from URLs and refuses a pass whose images it can't load. It can't
reach a dev server, so dev passes have none. In production:

- **The team logo** sits in the round spot beside the team name, from
  `/teams/:subdomain/logo`: padded to a transparent square, with a margin so the
  circle clips nothing. Google fills the transparency with white (tested 2026-10-01), so
  pages and Google share one image. It's public, like the logo on the team's D4H pages.
- **The photo** sits in the banner under the QR code (`heroImage`), from
  `/:code/banner` on the verify site, always SAR Duty's verify host: the square photo centered on the pass's navy. Google has no
  picture spot beside the name, so this is the only place on the front for both. Google
  keeps an image until its URL changes, so the URL carries `?v=`, from the card's
  `pass_updated_at` and `expires_at` (#1012). It moves on Refresh ID card and when the
  expiry rolls each month, and Google fetches the photo again.

## Issuing and emailing

Issue ID card and Email ID card each queue one job
([SendMemberCardWorker](../lib/app/worker/send_member_card_worker.ex), on `bulk`) that
emails the member one button, Get your ID card, to the card's page
([The card's page](#the-cards-page)). The email builds no pass and attaches nothing
([EmailMemberCard](../lib/app/operation/email_member_card.ex)).

| Member                      | Buttons                          |
| --------------------------- | -------------------------------- |
| No card                     | Issue ID card                    |
| Good standing, with a card  | Email · Refresh · Cancel ID card |
| Retiring or retired, a card | Cancel ID card                   |

- **Issue ID card**, for a member with no card, makes one. It checks the photo first,
  live, and makes no card without one ([A photo before a card](#a-photo-before-a-card)).
- **Email ID card** sends the current card again. No limit.
- **Refresh ID card**, while Wallet is set up, sends nothing by email
  ([Refresh ID card](#refresh-id-card)).
- **Cancel ID card**, red, on any card, makes no new one. A lost phone takes Cancel, then
  Issue, which the tab shows next (#1012: Replace ID card did both in one click, and it
  wasn't clear that it did). Its confirm says how they get a new card: "To give them a new
  one, select Issue ID card", or, with Every member gets a card on, "Your team gives every
  current member an ID card, so they get a new one at the next refresh." The confirm
  names the switch by what it does, since the switch's name means little this far from
  it. Cancel emails nothing, and history says who
  ([Active and qualifications](#active-and-qualifications)).

The card, as the member sees it from `/cards/:token/image`, sits beside its facts from a
tablet's width and above them on a phone, so a team admin can check the photo. The
buttons go under both.

Issue makes the card when clicked, mark it `email_status: :sending`, and queue
the job in the same transaction, so the tab shows the new card at once
([SendMemberCard](../lib/app/operation/send_member_card.ex)). The job emails the card only
while it is marked sending, so a retry, or a second job for the same card, sends one
email. A member with no email still gets a card, with no email. The job is unique per
member while it waits, so a click joins a job already waiting and moves it to now and to
the front of the queue.

The card keeps how its email went, `email_status` and `emailed_at`, like
`TaxCreditLetter.email_status`, and the tab's Emailed row shows it: when it went and to
whom, Sending, or that it did not send. A refusal is tried again over about 2 hours; the
last one marks it failed ([jobs.md](jobs.md)).

## The card's page

Every card email links to `sarduty.com/cards/<token>`
([CardLinkLive](../lib/web/live/card_link_live.ex), #952). Until then the email built
both passes and sent them: Google's badge at the top and the Apple pass attached under
the signature, where members missed it. Teams with ID cards and no member logins had no
other way to get the card.

- **The link is the key.** A signed `Phoenix.Token` naming the card's id, with its own
  salt and the reminders link's 5-year age ([Web.CardLinks](../lib/web/card_links.ex)).
  No login and no table, so nothing to migrate; the page is `noindex`.
- **The one place with the badges.** Your membership's Show ID card and the Dashboard's
  Add ID card to Wallet open this page, so a member learns one page, and on a computer
  gets its QR code rather than a pass iCloud carries to the phone. Show ID card shows
  whether or not a Wallet is set up, since the page has the card itself (#973).
- **Both badges on every device**, Apple's and Google's own (`<.wallet_badges>`,
  `/styles/wallet-badges`), side by side at 48px, Google's minimum, with no guessing which
  phone it is. Google's is its condensed button, two lines like Apple's, so the pair fits
  on one line on a phone. Apple has no wider badge for the web. Each opens
  `/cards/:token/apple-wallet` or `/cards/:token/google-wallet`
  ([CardLinkController](../lib/web/controllers/card_link_controller.ex)), which builds the
  pass on the tap. A mail app's link scanner or a preview only loads the page, so it
  builds nothing.
- **One quiet line says what SAR Duty sees**, above "Lost your phone?": "SAR Duty sees
  your ID card in Apple Wallet.", "…in Google Wallet.", "…in Apple Wallet and in Google
  Wallet.", or "SAR Duty doesn't see your ID card in Wallet yet."
  ([Web.WalletText](../lib/web/wallet_text.ex), which also writes the ID Card tab's
  Wallet row). It says whether a device holds the pass (`PassRegistration.holding/2`
  above 0), never how many: a pass added on an iPhone syncs through iCloud to the
  member's iPad, which registers on its own, so 1 added read as "2 devices". The ID Card
  tab keeps the count and the last download for team admins. The line changes while the
  page is open: a phone adding or dropping the pass, and Google's save and delete, each
  broadcast `:wallet_changed` on the card's topic (`MemberCard.pass_topic/1`). There's
  no refresh button: the page hears every change.
- **The line is never a spinner.** A tap can't tell an added card from a cancelled
  sheet, a file downloaded on a computer, or a card already in that Wallet, which
  registers nothing again. So the line only ever says what SAR Duty sees, and a tap
  starts a check, for 2 minutes, on a Wallet that doesn't hold the card yet. Google's
  save callback only reaches production, so the check asks Google every 4 seconds
  whether the pass has users
  ([CheckGoogleWalletSave](../lib/app/operation/check_google_wallet_save.ex)). That only
  ever marks a card saved: `hasUsers` may stay true after a delete, which the delete
  callback clears. Apple has nothing to ask; the phone registering is the news. A
  replacement lands on the cancelled card's pass with no new registration, so the check
  nudges those phones every 10 seconds (`PushPassUpdates.nudge_replacement/2`): it marks
  the pass updated and pushes, and a phone now holding the replacement fetches it with
  its token. On a Mac the pass reaches the phone through iCloud, so that can take 15
  seconds or more. Google's badge opens in a new tab, so the page stays open to hear
  the save.
- **The card itself, under the Wallet** (#973), for a member with no Wallet or one who
  wants a copy. [DrawMemberCard](../lib/app/operation/draw_member_card.ex) runs one
  Typst drawing, `priv/typst/member_card.typ`, for `/cards/:token/image`, a PNG at 400
  pixels an inch, and `/cards/:token/pdf`. Each is drawn on the request, as a pass is
  built, so it shows today's card.
  - **The picture is the front as the iPhone Wallet pass draws it**: upright, 54 × 74 mm,
    in the pass's navy with yellow labels and the team's name in yellow. Issued sits in
    the pass's Status place and Member since in the middle, at 7 pt; the third column,
    the pass's Valid until, stays empty. "No Wallet? Show this card,
    save it as an image, or print it." A member can show the page at the door as they
    would the pass. It draws its own round corners, with clear corners around them.
  - **The code under the QR code is IBM Plex Mono**, the app's font for codes, on the
    picture and the printed card; `priv/fonts` holds its Medium beside Arimo.
  - **One front, two looks.** The picture and the printed front show the same facts:
    the team's logo and name, the photo, the name, Member since, Issued, and the QR code
    with its code. Issued is the day the card was created (`inserted_at`), not the day
    it's drawn, so every copy of a card is the same; a replaced card gets a new date. A
    Try a demo card says "Sample, not real ID" over the name and "Sample card" for the
    team, as its passes do (#857).
  - **Nothing that changes.** No status, Valid until, Last updated, or endorsements: a
    copy never updates, so they would freeze ([Valid until](#valid-until)). The QR code
    is the check, and the verify page lists the endorsements.
  - **Save image**, under the picture, with the download icon in the arrow's place. On
    a phone it opens the share sheet, whose Save Image puts the picture in Photos
    (`SaveImage`, `assets/js/save_image.js`); a download would land in Files. On a
    computer it downloads. A long press on the picture saves it too.
  - **The printed card is CR80, across**: both sides 85.60 × 53.98 mm with 3.18 mm
    corners, the size of a plastic ID card, so it fits any card holder or sleeve. White
    under a 1 mm navy line with the team's logo and its name in navy, so any logo shows
    and any printer prints it. A long team name drops from 8 pt to 6.6 pt, and wraps only
    if it still doesn't fit. The back has the code again, so either side verifies, the
    name, How to verify, and Issued by, as the passes' backs say them, less "Status
    comes from the team's records" (`MemberCard.issuer/1`): the drawn card shows no
    status.
  - **Print ID card**, with the printer icon in the arrow's place, opens the PDF: a
    Letter page with both sides at actual size, each cut on its own edge, a dashed line
    with the card's rounded corners, so the piece is the card's size. A line further
    out would make a piece too big for a rigid card holder; the card keeps its text
    2.4 mm or more inside the edge for a crooked cut.
  - **Verify your ID card** opens the card's page on the verify site in the same tab,
    since the verify site is SAR Duty's own, as someone verifying it sees it. It was on
    Your membership until #973. With Lost your phone, it sits under Open on your phone
    on a computer, and under the card on a phone.
- **On a computer** the page is wider, with Take attendance's Open on your phone
  sidebar and the page's QR code (`<.open_on_device>`, `/styles/open-on-device`). It's
  hidden on a touch screen.
- **Only a live, active card offers passes** (`MemberCard.link_status/2`). A replaced
  card's page says to use the newest email, a cancelled one says it was cancelled, and a
  retired or retiring member's says it is not active; both send the member to a team admin. None shows a badge or the card,
  and the pass, picture, and PDF routes 404. A member who comes back gets the same card back, so its link works again.
- **Anyone with the link can add the card,** as anyone could open a forwarded pass. The
  page says the link is the member's alone, and Cancel ID card ends it.

## Every member gets a card

A team pilots ID cards with a few members, issuing each from their ID Card tab. Then a
team admin turns on **Every member gets a card** on team settings' Features tab, under ID
cards (#893). It shows only as off, and can't be turned on, while ID cards are off.
[IssueEveryMemberCard](../lib/app/operation/issue_every_member_card.ex) does the work.

- **Turning it on asks first, with the counts**: "Creates 40 cards and emails 38 members.
  2 have no email." From 10 emails up it waits on a check box, as every send to many
  members does (`send_confirm/3`). It then makes a card, in one transaction, for each
  member who is counted (a person, not retiring), current, has a photo, and has no live
  card, and queues a `SendMemberCardWorker` job to email each one with an address.
- **Members with no photo get no card yet** (#1012). Under the switch, "3 members have no
  photo, so they get no card yet." links to the built-in report Members without a photo.
  Hidden at 0. Each gets theirs at the first refresh after a photo is added.
- **Cards at once, emails after.** Making a card is database rows alone, so the ID Card
  tab and Your membership show it straight away. Each email job sends one email with a
  link and builds no pass (#952): passes are built as members tap, spread over days, so
  production's one shared CPU never builds 100 at once (#584). The `bulk` queue's limit
  of 2 paces the emails, at a lower priority, after any click, reminder, or letter.
- **While it's on, new members get theirs.** Each full refresh, and each sync that
  changed something, does the same for members without a card: someone new in D4H, or
  back from Retiring or retired with no card.
- **Members with no email still get a card.** They see it on Your membership, and the
  Features tab names them under the switch so a team admin can add an email in D4H.
- **Off stops new cards and cancels none.** Emails already queued still go. Issue,
  Replace, and Email card on the ID Card tab work either way.
- **Turning ID cards off turns it off too**, and turning ID cards back on leaves it off
  for a team admin to turn on again ([SetTeamIdCards](../lib/app/operation/set_team_id_cards.ex)).

The Dashboard's "Add your ID card to Wallet" to-do is the only follow-up. No reminder
email.

## Why the QR holds a link

Until 2026-10-01 the QR held only the code, so a forged card's QR couldn't open a
look-alike site: the checker had to open the check page first and scan from there.
We dropped that. Cards are for shops giving pro deals and for mutual aid teams. A clerk
whose camera shows a bare code gives up and looks at the pass instead, which is easier
to fake than a web page. A link gets them to the real check.

What's left: someone who scans a forged card with the plain camera and doesn't look at
the domain can be fooled by a look-alike site. The camera shows the domain before it
opens, the result page says to check the address bar, and partners who check often
should keep verify.sarduty.com on their home screen, where a forged link is flagged. For
mutual aid, a call to the member's team is the check; the card speeds it up.

## Valid until

The front of both passes reads **Status · Member since · Valid until**. The card SAR
Duty draws on its page, saves as an image, and prints (#973) leaves it off: a copy
never updates, so its Valid until would look expired on an active member, or current on
one who left. It shows the day the card was issued instead, and the QR code is the check. Valid until is
the end of the month three months after the team last checked D4H, shown as "Dec 2026"
in the team's zone ([MemberCard.valid_until/1](../lib/app/model/member_card.ex)). Apple
gets it as `expirationDate`, Google as `validTimeInterval.end`, and each marks the pass
expired once it passes.

- **It rolls with the refresh.** The date is part of the fingerprint, so each card gets
  one silent update a month from the push after a refresh. No `changeMessage`, no
  Google `notifyPreference`.
- **It comes from `d4h_refreshed_at`, not now.** Saving the endorsements page pushes too,
  and that shouldn't extend a card without a D4H check.
- **When refreshes stop, the pass expires** within three months: a broken D4H key, a
  team that leaves, a member who turns off updates.
- **It stops rolling once a card is not active** (#893). The card keeps the expiry its
  pass last had while active (`member_cards.expires_at`, `MemberCard.expires_at/2`), so a
  retired or retiring member's pass shows expired within three months. A member who
  comes back gets the same card back, active, and the date rolls again. A card first
  built after it went inactive starts from the refresh, once.
- Only an active card shows the date.
- Google sends the class only when a pass is added, so `UpdateGooglePasses` sends it
  again before any update. That's how a front-row change reaches passes already out.

## Active and qualifications

A card follows the member's standing (#893). It is active while the member is in good
standing: current, and not in the team's Retiring group, the same rule as logins (#514,
`Member.good_standing?/3` and `good_standing_query/2`). `MemberCard.status/3` asks it,
and the verify page, the JSON check, the door's scanner, and both passes read that.
Away and not a person don't change it.

- **Retired and retiring members keep their card.** It verifies as Not active at once,
  and its pass stops rolling Valid until. Retiring never cancels a card: Not active
  already pulls the QR code and fails every check, it says the true thing ("Retired Mar
  2027", where Cancelled hints at a lost card or a firing), and it undoes itself. A bad
  sync that marks many members retired fixes itself at the next sync; cancelled cards
  would stay dead, and a returning member would need a new code.
- **A team admin can cancel one by hand** (#964), for the rare member who shouldn't
  keep a card at all: until it expires, a Not active pass still looks like an official
  ID card, and scanning it shows their name and team. **Cancel ID card** on the ID Card
  tab works on any card since #1012, which also makes it the first step for a lost phone
  ([Issuing and emailing](#issuing-and-emailing)). It asks first in the app's dialog,
  then revokes the card, makes no new one, and queues `UpdateCancelledCardWorker` to void
  the Apple pass and expire the Google one
  ([CancelMemberCard](../lib/app/operation/cancel_member_card.ex)). The tab then says
  when the last card was cancelled, and the member's History says who.
- **A cancelled member who comes back has no card.** Every member gets a card issues
  them a new one, with a new code, as for anyone without a live card; the confirm says
  so when it's on. Otherwise a team admin issues one.
- **A member who comes back gets the same card back,** active, with no email.
- **A member not in good standing gets no new card**
  ([IssueMemberCard](../lib/app/operation/issue_member_card.ex) refuses), and the ID Card
  tab's Status row says why the old one is not active.

Qualifications don't change Active. They're listed, not required.

A team picks what to list on the **Endorsements** page (#320). For each endorsement the
member holds, the back of the pass, the verify site,
and the ID Card tab say when the member's latest current award ends, or that none is
current ([BuildCardQualifications](../lib/app/operation/build_card_qualifications.ex)).
Only the highest tier shows: when one held endorsement's qualifications are a strict subset
of another's, the stricter one stands for both, so First Aid (70 hours or higher) hides First
Aid (7 hours or higher). Nothing to set up; the lists decide it.
The pass shows them as of when it was made, and the verify site shows them as of the last
refresh.

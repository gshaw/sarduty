# Member ID cards

A team manager issues a member an ID card from the member's **ID Card** tab. Anyone can
check a card by scanning its QR code with a phone's camera, which opens its page on the
verify site, `verify.sarduty.com/K7Q4-M2XA`
([VerifyLive](../lib/web/live/verify_live.ex)), or by typing the code printed under it
at `verify.sarduty.com`. Issue #63 has the design and the plan. A team in a parent
organization gets its branding: see [organizations.md](organizations.md).

## What must stay true

- **The real check is the server's answer and the photo.** A pass is easy to fake with
  any pass-maker app. What can't be faked is sarduty.com saying the code is active and
  showing the member's face, so the result shows the photo large and tells the checker
  to look at the address bar.
- **The QR opens the card's page, and only the code is printed under it.** It holds
  `HTTPS://VERIFY.SARDUTY.COM/K7Q4-M2XA`
  ([MemberCard.qr_url/2](../lib/app/model/member_card.ex)), in capitals because a QR code
  packs capitals, digits, and `:/.-` into fewer squares. That fits the size-2 QR code.
- **The verify site serves only the check.** The router matches it by its `verify.`
  host ([Web.VerifyHost](../lib/web/verify_host.ex)). There's no login there, and the
  app's session cookie never reaches it, since that cookie is host-only. Other paths go to
  the app; a one-segment path reads as a code. The app's old `/verify` links redirect
  there, and the websocket's `check_origin` lists both hosts.
- **Scanning from the verify site is the careful check.** The page's scanner never
  follows a link. It takes the code out of a card's link (or an older `sarduty.com/verify`
  one), accepts a bare code from the first cards, and flags a link to anywhere else as
  forged.
- **Codes are random.** They come from `:crypto`, 8 characters from a 30-character
  alphabet ([MemberCard](../lib/app/model/member_card.ex)). Never derive one from the D4H
  member number or the local id: a guessable code would let anyone walk the roster.
- **Misses are capped per IP.** 20 codes that match no card in 10 minutes, on the page
  or the photo route, and that IP gets "Too many tries" with no lookup
  ([Web.VerifyLimit](../lib/web/verify_limit.ex)). Real codes never count, so checking a
  crowd of cards at a callout can't trip it. The counts live in memory (Hammer's ETS
  backend), which is enough on one machine and resets on deploy. The IP is Fly's
  `Fly-Client-IP`, read on the HTTP request and carried into the LiveView's session,
  since a websocket can't see that header.
- **A cancelled card shows nothing about the member.** `/verify` says it was cancelled,
  and its photo route 404s.
- **A former member's card shows no photo.** The page gives the name, the team, and "Not
  active", and the photo and banner routes 404, as for a cancelled card (#176). "Not
  active" is the whole answer a checker needs.
- **One live card per member.** Issuing a card revokes the one before it, and a code is
  never reused.
- **Status comes from the local copy of D4H**, so it can be a day old. The result says
  when the team last refreshed.

## Apple Wallet

The ID Card tab emails the current card's pass to the member's D4H address as an
attachment, or downloads it, when Apple Wallet is set up (see
[external-services.md](external-services.md)).

Passes update. Each pass carries a `webServiceURL` of `/wallet` and the card's
`authentication_token`. Wallet registers the phone with
[WalletController](../lib/web/controllers/wallet_controller.ex), and
[PushPassUpdates](../lib/app/operation/push_pass_updates.ex) pushes through APNs:

- **After every team refresh** it rebuilds each registered card's pass and pushes only
  when its fingerprint changed. The fingerprint leaves out the "last checked" date, or
  every pass would buzz every day.
- **When a pass is built** for an email, a download, or a phone, and its fingerprint
  changed, it pushes too. Building records the fingerprint, so the next refresh would
  otherwise see nothing new and the phones would keep the old pass.
- **On cancel or replace** it pushes right away, and Wallet fetches a voided pass that
  says "Cancelled".
- A phone that APNs says dropped the pass, or whose token is bad, is deleted.
- **A member keeps one Wallet serial number** across replacements, so a replacement pass
  lands on the existing pass instead of beside it. Each card has its own token, and a
  phone's token picks which card it gets, so a lost phone still holding the old token
  only ever gets the old card, voided. Cards made before this keep `member-card-<id>`.
- A pass made before updates existed has no token, so it never updates. Its card gets a
  token the next time its pass is built.
- APNs only works in production, so dev can build passes but never deliver a push.

The ID Card tab shows how many phones hold the pass and when one last fetched it
(`pass_fetched_at`). A phone's fetch broadcasts on PubSub, so the tab ticks over without
a reload. **Send test update**
([SendTestPassUpdate](../lib/app/operation/send_test_pass_update.ex)) sets `pass_test_at`
and pushes. The pass gains a "Test update" back field whose `changeMessage` puts a notice
on the lock screen. The fingerprint leaves that field out, so a test never makes a
refresh push, and the card's code, token and serial don't change.

Wallet has no CSS and shows images only as PNG, so
[LoadImage](../lib/app/operation/load_image.ex) shapes them with
[Service.Image](../lib/service/image.ex): the D4H photo cropped to a centered square, and
the team's saved logo converted to PNG, since D4H may send a JPEG. A missing or broken
image falls back to the placeholder photo or SAR Duty's logo. The member page, the team
dashboard, and tax credit letters use the same images, so what a manager sees is what
goes on the pass.

## Google Wallet

The ID Card tab's **Add to Google Wallet** sends the current card's pass to Google and
opens Google's save page. The email to the member has the same link, beside the Apple
pass. The link is a JWT that names the pass and nothing else; Google holds the pass
itself.

Google keeps the pass, so there's no phone to push to.
[UpdateGooglePasses](../lib/app/operation/update_google_passes.ex) sends Google a card's
pass again, and every saved copy changes:

- **After every team refresh**, for cards whose pass changed. The fingerprint leaves out
  the "last checked" date, as for Apple. A card with no `google_pass_fingerprint` has no
  pass at Google and is skipped.
- **On cancel or replace** the old pass is sent as `EXPIRED`, with no QR code or photo,
  and Wallet moves it to "Expired passes".
- **A replacement is a new pass.** Each card has its own Wallet object, because Google
  has no per-phone token to say which card a phone holds. The member adds the new one.

Google loads images from URLs and refuses a pass whose images it can't load. It can't
reach a dev server, so dev passes have none. In production:

- **The team logo** sits in the round spot beside the team name, from
  `/teams/:subdomain/logo`: padded to a transparent square, with a margin so the
  circle clips nothing. Google fills the transparency with white (tested 2026-10-01), so
  pages and Google share one image. It's public, like the logo on the team's D4H pages.
- **The photo** sits in the banner under the QR code (`heroImage`), from
  `/verify/:code/banner`: the square photo centered on the pass's navy. Google has no
  picture spot beside the name, so this is the only place on the front for both.

## Why the QR holds a link

Until 2026-10-01 the QR held only the code, so a forged card's QR couldn't open a
look-alike site: the checker had to open sarduty.com/verify first and scan from there.
We dropped that. Cards are for shops giving pro deals and for mutual aid teams. A clerk
whose camera shows a bare code gives up and looks at the pass instead, which is easier
to fake than a web page. A link gets them to the real check.

What's left: someone who scans a forged card with the plain camera and doesn't look at
the domain can be fooled by a look-alike site. The camera shows the domain before it
opens, the result page says to check the address bar, and partners who check often
should keep sarduty.com/verify on their home screen, where a forged link is flagged. For
mutual aid, a call to the member's team is the check; the card speeds it up.

## Valid until

The front of both passes reads **Status · Member since · Valid until**. Valid until is
the end of the month three months after the team last checked D4H, shown as "Dec 2026"
in the team's zone ([MemberCard.valid_until/1](../lib/app/model/member_card.ex)). Apple
gets it as `expirationDate`, Google as `validTimeInterval.end`, and each marks the pass
expired once it passes.

- **It rolls with the refresh.** The date is part of the fingerprint, so each card gets
  one silent update a month from the push after a refresh. No `changeMessage`, no
  Google `notifyPreference`.
- **It comes from `d4h_refreshed_at`, not now.** Saving Settings > ID cards pushes too,
  and that shouldn't extend a card without a D4H check.
- **When refreshes stop, the pass expires** within three months: a broken D4H key, a
  team that leaves, a member who turns off updates.
- Only an active card shows the date. An inactive card still gets the expiry, so a
  member who comes back still gets updates.
- Google sends the class only when a pass is added, so `UpdateGooglePasses` sends it
  again before any update. That's how a front-row change reaches passes already out.

## Active and qualifications

A card is active while the member hasn't left the team in D4H (`Member.current?/2`).
Qualifications don't change that. They're listed, not required.

A team picks what to list at **Settings > ID cards**: any named clause from its groups'
rules. Clauses that share a name count as one. For each, the back of the pass, `/verify`,
and the ID Card tab say when the member's latest current award ends, or that none is
current ([BuildCardQualifications](../lib/app/operation/build_card_qualifications.ex)).
The pass shows them as of when it was made, and `/verify` shows them as of the last
refresh.

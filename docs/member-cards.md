# Member ID cards

A team manager issues a member an ID card from the member's **ID Card** tab. Anyone can
check a card at `/verify` ([VerifyLive](../lib/web/live/verify_live.ex)) by scanning its QR
code or typing the code printed under it. Issue #63 has the design and the plan.

## What must stay true

- **The checker starts at sarduty.com.** A forged card can carry a QR code that opens a
  look-alike site, so the QR holds only the code, never a URL, and `/verify` reads it with
  the camera instead of following it. Don't add a link to a card that opens the result.
- **Codes are random.** They come from `:crypto`, 8 characters from a 30-character
  alphabet ([MemberCard](../lib/app/model/member_card.ex)). Never derive one from the D4H
  member number or the local id: a guessable code would let anyone walk the roster.
- **A cancelled card shows nothing about the member.** `/verify` says it was cancelled,
  and its photo route 404s.
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

Wallet shows images only as PNG. The photo comes from D4H and the logo from the team's
saved logo, both as D4H sent them.

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

Google loads the photo from `/verify/:code/photo`, the public one `/verify` shows, and
refuses a pass whose photo it can't load. It can't reach a dev server, so dev passes have
no photo. Team logos aren't public, so the Google pass shows the team's name, not its
logo.

## Active and qualifications

A card is active while the member hasn't left the team in D4H (`Member.current?/2`).
Qualifications don't change that. They're listed, not required.

A team picks what to list at **Settings > ID cards**: any named clause from its groups'
rules. Clauses that share a name count as one. For each, the back of the pass, `/verify`,
and the ID Card tab say when the member's latest current award ends, or that none is
current ([BuildCardQualifications](../lib/app/operation/build_card_qualifications.ex)).
The pass shows them as of when it was made, and `/verify` shows them as of the last
refresh.

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
[external-services.md](external-services.md)). The pass is a snapshot: it doesn't update
after it's added, and cancelling a card doesn't void a pass already on a phone. `/verify`
still says the card was cancelled. Updates need Apple's pass web service, which is next
on #63.

Wallet shows images only as PNG. The photo comes from D4H and the logo from the team's
saved logo, both as D4H sent them.

## Active and qualifications

A card is active while the member hasn't left the team in D4H (`Member.current?/2`).
Qualifications don't change that. They're listed, not required.

A team picks what to list at **Settings > ID cards**: any named clause from its groups'
rules. Clauses that share a name count as one. For each, the back of the pass, `/verify`,
and the ID Card tab say when the member's latest current award ends, or that none is
current ([BuildCardQualifications](../lib/app/operation/build_card_qualifications.ex)).
The pass shows them as of when it was made, and `/verify` shows them as of the last
refresh.

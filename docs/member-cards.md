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

## Active

A card is active while the member hasn't left the team in D4H (`Member.current?/2`).
Which qualifications a team also requires is still open on #63.

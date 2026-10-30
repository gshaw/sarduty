# Tax credit letters

A team manager makes each member's tax credit letter, a PDF the member gives the CRA.
Anyone holding one can verify it on the verify site: the letter's QR code opens
`verify.sarduty.com/letters/SRVTC-K7Q4M2XA`
([VerifyLetterLive](../lib/web/live/verify_letter_live.ex)), or they type the reference
number at `verify.sarduty.com/letters`. Issue #207 has the design. How hours are
counted is in #191, #192, and #584, and #594 explains it publicly for anyone who asks.

## What must stay true

- **Time counts once, and chores add up**
  ([CountTaxCreditHours](../lib/app/operation/count_tax_credit_hours.ex)). A member's
  rows go on one timeline, where overlapping time counts once and primary wins over
  secondary (#191). Chore rows never go on it: each one starts at 00:00 on the 1st, a
  made-up time, so they are added up (#584). SAR Duty knows them by its chore events,
  never by tag. A team's own bulk-hour activities count like any activity. A change to
  these rules changes #594 too, the public explanation.

- **The check page is the real protection, not the PDF.** The PDF is locked print-only
  ([Service.PDFLock](../lib/service/pdf_lock.ex), AES-256 with no open password), but
  that only stops casual edits in Acrobat: unlock tools strip it, and anyone can retype
  a letter. What can't be faked is the page showing the hours the team issued.
- **Reference numbers can't be guessed.** `SRVTC-` and 8 characters from the ID card
  alphabet, from `:crypto` (`TaxCreditLetter.generate_ref_id/0`). The page shows a
  member's name and hours, so a guessable number would let anyone walk the roster.
- **Old reference numbers need the last name too.** Letters before #207 have 5
  characters from `Service.Random.token/1`, about 2 million, never checked for
  duplicates. The page asks for the member's last name before it shows one. The unique
  index on `ref_id` covers only the 8-character numbers for the same reason.
- **Only the current letter verifies.** Replace gives the letter a new reference number,
  and Delete ([DeleteTaxCreditLetter](../lib/app/operation/delete_tax_credit_letter.ex))
  removes it. Either way the old number is not found, so an old paper copy can't pass for
  the hours the team stands behind now. Both ask for a ticked box, since the member may
  already have the letter.
- **Letters stay off the ID card pages.** `/letters` is its own page on the verify host,
  so it gets the host's isolation (no login cookie), its miss limit
  ([Web.VerifyLimit](../lib/web/verify_limit.ex), shared with cards), and an
  organization's own verify host when that ships. The card pages don't mention letters.
- **Hours print as the letters table shows them**, from `Service.Format.duration/1`:
  "212h 30m", or "202 hours" when there are no minutes (#260). Nothing is rounded, so
  the letter, the verify page, and the saved minutes agree. `TaxCreditLetter.parse_minutes/1`
  reads this and the older "212 hours, 30 minutes".
- **The letter cites the Act, not a police force.** "An eligible search and rescue
  organization under subsection 118.07(1) of the Income Tax Act" is true in every
  province. A letter's text is saved when it's made, so changing the wording never
  changes a letter already issued.
- **Letters name the team by its legal name** (#738), `legal_name`: the body, the signer
  fallback, the PDF's title, author, and filename, the email, and the verify page. A team
  sets it in team settings › General. It starts as the team's name, and nothing checks
  it, so a team that shortened its name fixes it by hand before letter season.
- **The letterhead is the organization's logo, then the team's** (#290), top right. Either
  is left out when it's missing, and a team without a logo never gets SAR Duty's. Logos
  are the current ones when the PDF is built: a letter saves its text and signature, not
  its logos.
- **The QR code is drawn, not an image.** Vector squares from `eqrcode`'s matrix, beside
  the signer block, so it prints sharp. It holds the URL in lower case, since the
  `/letters` path is case-sensitive. Letters from before #207 get none.

- **A member's download is recorded** (#389): the first time a member downloads their
  letter from their own pages sets `downloaded_at`, and the letter leaves their For you
  to do. Only the newest letter shows there, and only for last year or this year. A team
  admin's download doesn't count. A replaced letter is a new row, so it shows again.

## The PDF package's limits

The `pdf` package escapes parentheses but not backslashes, and writes the title and
author as raw UTF-8, which readers show garbled. Page text can't hold characters outside
WinAnsi, such as `ʼ` (U+02BC). None of this matters for letters today; it would for a
team or member name with accents in the title.

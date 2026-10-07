# Tax credit letters

A team manager makes each member's tax credit letter, a PDF the member gives the CRA.
Anyone holding one can verify it on the verify site: the letter's QR code opens
`verify.sarduty.com/letters/SRVTC-K7Q4M2XA`
([VerifyLetterLive](../lib/web/live/verify_letter_live.ex)), or they type the reference
number at `verify.sarduty.com/letters`. Issue #207 has the design. How hours are
counted is in #191 and #192.

## What must stay true

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
- **A letter that's out keeps verifying.** Replace gives the letter a new reference
  number and saves the old number, hours, and certified date in
  `replaced_tax_credit_letters`. The old number shows "This letter was replaced" with the
  hours it said, so a paper copy already handed in still matches. Delete removes a
  letter and its replaced numbers; its confirm warns that the member may have it.
- **Letters stay off the ID card pages.** `/letters` is its own page on the verify host,
  so it gets the host's isolation (no login cookie), its miss limit
  ([Web.VerifyLimit](../lib/web/verify_limit.ex), shared with cards), and an
  organization's own verify host when that ships. The card pages don't mention letters.
- **The QR code is drawn, not an image.** Vector squares from `eqrcode`'s matrix, beside
  the signer block, so it prints sharp. It holds the URL in lower case, since the
  `/letters` path is case-sensitive. Letters from before #207 get none.

## The PDF package's limits

The `pdf` package escapes parentheses but not backslashes, and writes the title and
author as raw UTF-8, which readers show garbled. Page text can't hold characters outside
WinAnsi, such as `ʼ` (U+02BC). None of this matters for letters today; it would for a
team or member name with accents in the title.

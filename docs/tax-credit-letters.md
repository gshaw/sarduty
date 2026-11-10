# Tax credit letters

A team manager makes each member's tax credit letter, a PDF the member gives the CRA.
Anyone holding one can verify it on the verify site: the letter's verify code opens
`verify.sarduty.com/K7Q4M-2XA9H-VB3TN` ([VerifyLive](../lib/web/live/verify_live.ex)),
or they type the ID at `verify.sarduty.com`. Issue #207 has the design, and #970 moved
letters onto [published PDFs](documents.md#published-pdfs). How hours are
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
- **IDs can't be guessed.** A letter's ID is its PDF's: 15 characters from the ID card
  alphabet, from `:crypto` (`PublishedPDF.generate_code/0`). The page shows a member's
  name and hours, so a guessable ID would let anyone walk the roster.
- **Old reference numbers never verify** (#970). Letter verify shipped on 2026-10-07
  (#207), and few letters with a verify code went out, all test letters, so the
  `SRVTC-` numbers and the last-name check for the 5-character ones before #207 went.
  Each letter from before #970 got an ID and its saved PDF printed again with the new
  verify code, once, after part 1 of #970 deployed, so no saved PDF carries a dead code.
- **A letter is its published PDF** (#970): a row in `published_pdfs` named `Tax credit
letter`, for its member's year, `member:45:2026` ([App.Model.TaxCreditLetter](../lib/app/model/tax_credit_letter.ex)
  has its queries and rules). Its ID, the hours it kept, its date, who published it, its
  email status, and when its email last went (`emailed_at`) are on it.
- **A member's year has one page, sent or not** (#970),
  `/tax-credit-letters/:year/members/:id` ([TaxCreditLetterLive](../lib/web/live/tax_credit_letter_live.ex)),
  which the name in the letters list opens. With a letter it has the Published box a
  form's page has, where its email is, and Out of date with each hour that changed.
  With none, it shows the letter as it prints today, marked DRAFT, with no signature,
  and Send letter. Page 1 shows either way, drawn from the PDF when the page asks
  (`Service.PDFImages.first_page/2`), so nothing more is saved. History lists every
  letter for the year from their own dates ([PublishedHistory](../lib/app/view_data/published_history.ex)).
- **The letters list says where each letter is, in a word**: No letter, Emailed, or Not
  emailed, with a badge when it needs a team admin: Out of date, Did not send, or No
  email. Each tile is a to-do (No letter, Not emailed, Out of date), and a member can be
  in two; emailed letters show under All.
- **Check, then act** (#970, as an activity's Members tab): team admins check members,
  or a tile then select all, and pick one of For the checked members: Send letters,
  Email letters, or Publish again. Each counts only the checked it fits, a choice that
  fits none greys out and says why, and one button in the action bar does it. Send
  letters runs in a job, Publish again in the page's background since each prints a
  PDF, and every email has its own job
  ([CreateTaxCreditLetters](../lib/app/operation/create_tax_credit_letters.ex)).
- **Only the current letter verifies as current.** Publish again
  ([PublishTaxCreditLetter](../lib/app/operation/publish_tax_credit_letter.ex)) prints a
  new letter with a new ID, and the old one's verify page says Replaced and shows
  nothing from it, so an old paper copy can't pass for the hours the team stands behind
  now. Withdraw ([WithdrawDocument](../lib/app/operation/withdraw_document.ex)) ends one
  with no new one, and its member lists under No letter again; it asks for a ticked box,
  since the member may already have the letter. Publish again emails the new letter, so
  the member never keeps one that verifies as Replaced. Nothing deletes a letter but its
  team's purge.
- **Out of date is what the verify page would show** (#995), as for every published
  PDF: the letter, read today, would put different `verify shows` values on its verify
  page, such as its hours or the member's name (`TaxCreditLetter.changes/4`, from
  `PublishedPDF.changes/2`). A team's postal code or a new signer is not on it, so it
  changes nothing. A closed year's letters, older than last year's, never go out of
  date: a member may have filed one (#192). Nothing publishes a new one by itself.
- **The letters list reads every letter at once** (`PrintTaxCreditLetter.read_each/4`):
  the document checked once, the team's values and pictures read once, and the year's
  hours counted once for every member shown, then each member's own reports. On South
  Fraser's 75 to 87 members a year it takes 72 to 76 ms, where reading each letter alone
  took 1.6 to 1.9 s (21 to 24 ms each), measured on 2026-11-10.
- **Letters verify at the verify site's root**, beside cards, so they get the host's
  isolation (no login cookie), its miss limit ([Web.VerifyLimit](../lib/web/verify_limit.ex),
  shared with cards), and an organization's own verify host when that ships. An old
  letter's link, `/letters/:ref`, is not found.
- **Hours print as the letters table shows them**, from `Service.Format.duration/1`:
  "212h 30m", or "202 hours" when there are no minutes (#260). Nothing is rounded, so
  the letter, the verify page, and the saved minutes agree.
- **The letter cites the Act, not a police force.** "An eligible search and rescue
  organization under subsection 118.07(1) of the Income Tax Act" is true in every
  province. A letter's text and PDF are saved when it's made, so changing the wording
  never changes a letter already issued.
- **The letter is a document**, [tax_credit_letter.txt](../priv/documents/tax_credit_letter.txt)
  ([documents.md](documents.md)): what it reads, its wording, where each part sits,
  and worked examples CI checks. Making a letter runs it once
  ([PrintTaxCreditLetter](../lib/app/operation/print_tax_credit_letter.ex)): the
  saved text, the hours it keeps, and the PDF all come from the same values. Typst
  prints it in Arimo, so every name prints, whatever its letters (#917).
- **Letters name the team by its legal name** (#738), `legal_name`: the body, the signer
  fallback, the PDF's title, author, and filename, the email, and the verify page. A team
  sets it in team settings › General. It starts as the team's name, and nothing checks
  it, so a team that shortened its name fixes it by hand before letter season.
- **The letterhead is the organization's logo, then the team's** (#290), top right. Either
  is left out when it's missing, and a team without a logo never gets SAR Duty's. Logos
  are the ones the team has when the PDF is drawn, and the saved PDF keeps them.
- **Making a letter publishes it** (#918, #970): its PDF prints once with a new ID and
  is kept as it was made, one of the [published PDFs](documents.md#published-pdfs). It prints before the write transaction, which holds SQLite's one
  write lock, and a print that fails makes nothing
  ([PublishTaxCreditLetter](../lib/app/operation/publish_tax_credit_letter.ex)).
  Downloads and emails serve the saved file, so a member gets the same file every time.
  A team admin downloads any published PDF, a letter's or a form's, from `/pdfs/:id`.
- **The email's words are the letter's** (`email to member` in its document, #970):
  what it's for, the CRA line, and who answers questions. Send letters gives each
  letter its own email job, and its row says when it went or didn't; Email letter sends
  it again, and a refusal there says Did not send at once. A member with no email gets a
  letter that isn't emailed.
- **The team settings a letter needs are the letter's** (`needs`, #943, #970): Needs
  attention names each blank one from January to April.
- **The signature is the team's when the PDF is printed**, and the saved PDF keeps it.
  The letter keeps no copy of its own (#918).
- **The verify code is a published PDF's** (#970), bottom left: a vector QR code, an
  SVG from `eqrcode`, so it prints sharp, then "Verify this document" and the link. Its
  verify page shows the member's name, the year, and the hours, from the letter's
  `verify shows`.

- **No download tracking, and no For you to do item** (#389, dropped in #970): the
  email attaches the PDF, so publishing is the notice. A member with no email shows in
  Needs attention ("N members have no email, mobile phone, or address") until one is
  added. The letter stays on Your membership with Download letter all year.

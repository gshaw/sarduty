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
  which the name in the letters list opens. Out of date and Needed to publish are
  warning banners under its title (#995). With a letter it has the Published section a
  form's page has ([PublishedPDF component](../lib/web/components/published_pdf.ex)):
  when and who, its ID, where its email is, Download PDF, Email letter, and Withdraw
  letter. With none, Not published and Email letter. A member with no email gets
  Publish letter, the same action. Page 1 is open under it either way: the saved PDF,
  drawn when the page asks (`Service.PDFImages.first_page/2`), or the letter as it
  prints today, marked DRAFT, signed as the letter will be. The draft is
  only a picture, never a download. History lists every letter for the year from their
  own dates ([PublishedHistory](../lib/app/view_data/published_history.ex)): published,
  published again, and withdrawn. Emails aren't History, since a letter keeps only its
  last one (`emailed_at`); the Published section says when it last went, and to whom.
- **The letters list says where each letter is, in a word**: No letter, Emailed, or Not
  emailed, with a badge when it needs a team admin: Out of date, Did not send, or No
  email. Two tiles split the members with hours (#995): Emailed, whose letter went by
  email and is up to date, and To email, everyone else. Nothing in the tiles is special
  for a member with no email: they stay in To email, with the No email badge.
- **Letters have two actions, Email and Withdraw** (#995), on the list and the letter
  page ([EmailTaxCreditLetters](../lib/app/operation/email_tax_credit_letters.ex)).
  Email sends each member their latest letter as a PDF, publishing a new one first when
  there's none or it's out of date, so no member keeps a letter that verifies as
  Replaced. An up-to-date letter goes again. A member with no email gets a published
  letter on Your membership only, and one with no hours that year gets nothing. "Send"
  is D4H's word, so letters say email. There's no Publish on letters, and no way to
  make a letter available without emailing a member who has an email.
- **The list opens on the letter year** (#995, `TaxCreditLetter.list_year/2`), and the
  Tax credit letters menu with it: last year from January to April, while its letters
  go out and members file by April 30; this year from May, while hours still grow and
  members can still reach the 200-hour mark. It turns over in the team's time zone. Any
  other year is one Year filter away.
- **A year that isn't over has no actions** (#995): until it ends in the team's time
  zone, its hours can grow, and its letters would need publishing again. Only Email
  publishes a letter, so none can be withdrawn either. The list has no boxes, choices,
  or button, and says "2026 letters can be emailed from January 1, 2027."; the letter
  page shows that sentence in place of Email letter and Withdraw letter. The operation
  refuses Email too. A draft still prints.
- **Check, then act** (#970, as an activity's Members tab): team admins check members,
  or a tile then select all, and pick Email letters or Withdraw letters under For the
  checked members. Each counts only the checked it fits, a choice that fits none greys
  out and says why, and one button in the action bar does it. Email for many runs in a
  job, since each new letter prints a PDF, and every email has its own job. On the
  letter page, Email publishes and emails at once.
- **Every Email and Withdraw asks first** ([Web.TaxCreditLetterConfirm](../lib/web/tax_credit_letter_confirm.ex)):
  Email names who gets what, up to 3, then a counted line per group by what happens,
  with anyone not emailed on their own line, and a box from 10 emails. Withdraw asks
  for a box from 1, naming the count: nothing takes its place. There's no preview page
  before emailing a letter: the letter page shows Page 1.
- **Only the current letter verifies as current.** A new letter
  ([PublishTaxCreditLetter](../lib/app/operation/publish_tax_credit_letter.ex)) prints
  with a new ID, and the old one's verify page says Replaced and shows nothing from it,
  so an old paper copy can't pass for the hours the team stands behind now. Withdraw
  ([WithdrawDocument](../lib/app/operation/withdraw_document.ex)) ends one with no new
  one, and its member lists under No letter again. Nothing deletes a letter but its
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
  what it's for, the CRA line, and who answers questions. Email on the list gives each
  letter its own email job, and its row says when it went or didn't; on the letter
  page it sends at once, and a refusal there says Did not send at once.
- **What a letter needs blocks publishing it, never a draft** (`needs`, #943, #995):
  `team.mailing_address, team.signer, team.signer_title`. While one is blank, no letter
  is published, so none is emailed; letters already published stay as they are. The
  list and the letter page say so in a warning banner, Needed to email (Needed to
  publish for a member with no email), linking the tab that fills each, and Email says
  the same as an error. Needs attention says "Tax credit letters cannot be emailed until
  you add the signer's title" from December to April, so it's fixed before January 1.
  The address is on team settings' General tab, and who signs on Signer.
- **The signer signs by typing their name** (#995): every letter prints "/s/ Alex Chen"
  in Dancing Script, bold, under Certified on, then the name, title, phone, and email.
  BCSARA said the CRA wants a signature, and no team admin has to upload a picture: on
  2026-11-10 only one of the 10 teams that sent letters had one. The Signer tab
  ([SignerLive](../lib/web/live/settings/signer_live.ex)) shows the end of every letter
  as it's typed, and a test checks it against the letter's own text. The signer is one
  line: the migration that dropped the picture kept the first line, up to a comma, and
  moved a title, phone, or email it held to its own field. A form is signed by its task
  leader, by hand, never by the team's letter signer.
- **Signed by is not on the verify page.** A new signer would make every letter out of
  date, since out of date is what the verify page would show.
- **The verify code is a published PDF's** (#970), bottom left: a vector QR code, an
  SVG from `eqrcode`, so it prints sharp, then "Verify this document" and the link. Its
  verify page shows the member's name, the year, and the hours, from the letter's
  `verify shows`.

- **No download tracking, and no For you to do item** (#389, dropped in #970): the
  email attaches the PDF, so publishing is the notice. A member with no email shows in
  Needs attention ("N members have no email, mobile phone, or address") until one is
  added. The letter stays on Your membership with Download letter all year.

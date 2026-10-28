# Certificates

A member sends a certificate, such as a renewed First Aid, and a team admin accepts it
into D4H as an award with the file attached, or declines it with a reason the member
sees (#493). They exist only on a team with member logins and
certificates turned on, in team settings' Features tab; every team starts with both off.

## Sending

A member sends one from Your membership, Add a certificate:
`/teams/:subdomain/certificates/new`
([CertificateFormLive](../lib/web/live/certificate_form_live.ex),
[SaveCertificate](../lib/app/operation/save_certificate.ex)). A team admin who is a member
gets the same button on Certificates (#645). The form and the file have one URL each for
everyone: `/certificates/:id/edit` for the member's own while it waits, and
`/certificates/:id/file`, which gives a team admin any of the team's and anyone else only
their own. They were under `/me` until 2026-10-28, gone with no redirects.

- **The file first**, then the qualification, the dates, and a note.
- **The qualification is optional.** A team has over 100, and members are not always
  sure which one a course is. Not sure? They leave it blank, and a note for the team
  admin says which course it was. The list is any of the team's qualifications, the
  member's own first, organisation-owned ones too: D4H takes an award of either with the
  team's key (tried on South Fraser, 2026-10-21).
- **No warnings about dates on the member's form.** A certificate can be odd and still
  right; the team admin checks it.
- **The expiry fills in** from D4H's `expiresMonthsDefault` for the qualification, or
  else the length of the member's last award of it, until the member types their own.
- **One file drop** (`<.file_drop>`, every upload's): drop the file, paste it, or select
  the button. `accept="image/*,application/pdf"`, with no `capture` attribute: that
  forces the camera and blocks PDFs. Phones offer the camera themselves.
- **Waiting, Accepted, Declined.** A waiting certificate sits at the top of the member's
  Qualifications table, with a Waiting tag, and they change or delete it until its award
  is in D4H. A declined one shows why until they delete it.

## The file

[Service.CertificateFile](../lib/service/certificate_file.ex) decides the type from the
file's first bytes, never its name. A PDF is kept as it came. A photo is turned the way
the camera held it, shrunk to 2000 px, and saved as a JPEG without its metadata (GPS,
camera). HEIC goes the same way when the bundled libvips reads it, and is refused
otherwise. Up to 10 MB, and a photo up to 120 million pixels, read from its header before
anything is decoded; anything else is refused.

- **Kept only while it waits**, in `certificate_files`, apart from `certificates` so
  lists never load it. Accepting or declining deletes it. After that D4H holds it.
- **Served only to the member and the team's admins**, with the headers of the
  Certificate links (#434), `Content-Security-Policy: sandbox` among them
  ([Web.CertificateResponse](../lib/web/certificate_response.ex)). The team admin's page
  shows a photo as an image and a PDF in a frame, in the browser's own viewer. The frame
  has no `sandbox` attribute: that one blocks Chrome's PDF viewer, which runs scripts,
  while the header alone does not (Chrome 155, 2026-10-23).
- **A sideways photo turns.** EXIF turns a photo the way the camera held it, but a
  landscape certificate shot with the phone upright has nothing to say so. While it
  waits, the team admin's page has Rotate left and Rotate right above a photo, which turn
  the kept JPEG (`SaveCertificate.rotate/3`), so it goes to D4H the right way up. A PDF
  has none: the browser's viewer turns it.
- **Never in MCP output.**

## Accepting

A team admin opens a certificate from Certificates, `/teams/:subdomain/certificates`,
and sees the file beside its dates and the member's award D4H has now
([CertificateLive](../lib/web/live/certificate_live.ex)). They pick or change the
qualification and dates, then accept it
([AcceptCertificate](../lib/app/operation/accept_certificate.ex)).

- **The file on a grey mat**, at most 70% of the screen tall, so white paper shows its
  edge and a phone photo fits. Selecting it opens it at full size. The details and the
  decision sit beside it from 64rem, under it below that.
- **A box the team admin selects** before accepting: "I checked the certificate. It is
  Standard First Aid, Oct 18, 2026 to Oct 18, 2029." It names what goes, since only D4H
  can change an award once it is there. It clears when the qualification or dates change
  after it was selected. Nothing keeps it.
- **The qualification's hint** says whether the member picked it, and when the member
  has never held it: "New for Sam: no award of it yet."
- **The expiry fills in** as on the member's form when the team admin picks another
  qualification (Web.CertificateExpiry).
- **Dates that look wrong are a warning, never an error**: a start after today, an
  expiry more than a month off the qualification's usual length, or no expiry when it
  usually has one (`Certificate.date_warnings/4`). An expiry already past is fine: it goes
  in as a past award, and the hint says so.
- **Wrong after all?** An accepted certificate's page links to the member in D4H, where
  the award is fixed.

- **One change set, applied at once** (source `certificates`): `award_qualification`,
  then `attach_award_document`, which uploads the file to the award the first row made
  ([change-sets.md](change-sets.md)). Then SAR Duty puts the award in its copy with its
  `d4h_document_id`, so pages, group rules, and ID cards see it before the next refresh,
  and deletes the file.
- **D4H already has the award** when it holds the member's award of the same
  qualification from the same day, read as the page opens
  ([FindCertificateAward](../lib/app/operation/find_certificate_award.ex)). With no
  certificate on it, Attach certificate puts the file on that award and adds no second
  one: the set is the upload alone. With one, the team admin declines.
- **The same day is the award's UTC date**
  ([QualificationAward.starts_on?/2](../lib/app/adapter/d4h/qualification_award.ex)),
  for the page and the set alike. D4H keeps award dates at midnight UTC, the day before
  on a Canadian clock. SAR Duty's own awards start at midnight on the team's clock: the
  same UTC date in every Canadian time zone.
- **Never an award twice.** D4H's API can't remove one. Accepting reads D4H again before
  it writes, and the set skips an award D4H has from the same qualification and day.
  When the upload fails, the award stays and the certificate keeps waiting with its file;
  its dates lock, and Send again applies the same set, so only the upload goes.
- **One change at a time.** An accept holds a lock on the certificate while it waits on
  D4H. A member's change or delete, and another team admin's decline, wait for it, then
  read the certificate again.
- **Nothing changes an accepted certificate in SAR Duty.** A wrong award is fixed in D4H.
- **Until accepted, group rules and ID cards use what D4H has.** A waiting certificate
  doesn't expire; the count keeps it in view.

## Where else certificates show

- **Team home**: "N certificates to accept" under Needs attention, and the waiting count
  beside Certificates in the side navigation. For a member, "Your X expires in N days"
  under For you to do opens the form for that qualification, and leaves while a
  certificate for it waits. A declined certificate shows there until they delete it.
- **SAR Duty Records**: a team admin's Award a qualification form on a member's
  Qualifications tab takes an optional certificate, uploaded once the award is in.
- **Search** finds a certificate by its qualification or member, for team admins.
- **Privacy**: SAR Duty keeps a certificate only until a team admin accepts or declines
  it.

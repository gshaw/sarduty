# Member logins

A team admin turns on member logins in **Team settings → Member logins**. Then every
current member of the team can log in with the email or mobile number D4H has for them,
and land on their own page, `/teams/:subdomain/me`
([MeLive](../lib/web/live/me_live.ex)). It shows the ID card a team admin issued them,
with the Wallet buttons, their tax credit letters as PDFs, their hours and activities for a
year, and their qualifications. On `/teams/:subdomain/me/details` they change their
mailing address and emergency contacts in D4H, and on `/teams/:subdomain/me/mobile` their
mobile number. Members don't change their email: teams keep it consistent, and team
admins change it in D4H. Issue #156 has the design.

## What must stay true

- **A member page shows only the person logged in.** `member` comes from the login, in
  `on_mount(:ensure_team_member, …)` and the `require_team_member` plug
  ([Web.UserAuth](../lib/web/user_auth.ex)). No member page or download takes a member id
  from the URL. A letter is found by its id and the member's id together
  ([TaxCreditLetter.find_for_member!/2](../lib/app/model/tax_credit_letter.ex)).
- **Admins get no pass.** A SAR Duty admin reaches every team page, but not another
  person's member page.
- **Who logs in as a member is one query**:
  [Member.get_logins/2](../lib/app/model/member.ex). The team has member logins on, and
  the member is current, isn't retired, and isn't marked not a person. Two such members on
  one team with the same email match neither, since SAR Duty can't tell whose card to
  show. `Accounts.may_log_in?/2` uses it, so emailed and texted codes both work.
- **Every request checks again.** Turning member logins off, or the refresh seeing a
  member leave, ends access on the next page. Getting a card checks the login again, in
  case the page was open when access ended.
- **Member pages are outside the team pages' `live_session`.** They never set
  `current_team`, so the top bar shows team sections only to the team's admins. A team
  admin is a member too, and reaches their own page from the account menu.
- **Members don't issue cards.** Issuing, replacing, and cancelling stay with team admins,
  on the member's ID card tab, and only on a team a SAR Duty admin turned ID cards on for
  ([member-cards.md](member-cards.md)).
- **Member visits don't count as team use.** `RecordUserSeen` isn't called from member
  pages, so `/admin` still shows which teams' admins use SAR Duty.
- **Hours match the letter.** The page counts with `CountTaxCreditHours`, as the letter
  and the letter list do, so a member sees the number their letter will say. Their
  records come from [MemberRecords](../lib/app/view_data/member_records.ex), which filters
  by the member and their team.
- **A member's own edits go straight to D4H.** Saving their details is a change set of
  source `:member`, proposed and applied in one step by
  [SaveOwnDetails](../lib/app/operation/save_own_details.ex), with the member's user on
  it. D4H records SAR Duty's key as the editor, so the change set is the record of who
  asked. Only the fields that changed go, with D4H's old values.
- **Emergency contacts are never copied.** The details page reads them from D4H each time
  it opens. The change set row keeps the old and new contact, as every row keeps what it
  changed. SAR Duty Records has no emergency contacts, so its members change only their
  address.
- **A new mobile number needs a code first.** Text login uses it, so
  [ChangeOwnPhone](../lib/app/operation/change_own_phone.ex) texts a code to the new
  number, a `"confirm"` user token that lives and dies like a login code, with the login
  rate limits. Only a matching code sends the change to D4H. The member's email then gets
  a notice, in case someone else made the change.

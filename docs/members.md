# Members

The members list and a member's page, for team admins, and member logins, for members.

## The members list

`/teams/:subdomain/members` ([MemberCollectionLive](../lib/web/live/member_collection_live.ex),
[MemberFilterViewModel](../lib/app/view_model/member_filter_view_model.ex)) answers
questions with general filters and sortable columns rather than one Needs attention item
each (#367): "who in Callout is drifting away?" is Group: Callout sorted by Last attended.

- **Last attended** is the start of the latest activity the member attended, any kind
  (incidents, exercises, events), not deleted. Showing up to anything is the sign it is
  for. It comes from a join on `Member.last_attended_query/1`, so it sorts, and never
  attended sorts first going up. The member's page shows the same date.
- **Period** sets what Activities and Duration count, and limits the list to members on
  the team at some point in it: All, the last 30, 60, 90, 180, or 365 days (`when=90d`),
  or a year (`when=2026`, the default this year). It replaced Year, so old year links
  open the same list. A team that wants departed members uses Status.

## Standing

A member's **standing** says whether the team expects them to show up now (#366):
**Active**, **Away** for a dated period such as leave, or **Not a person**. Decided
2026-10-18; the issue has the reasons.

- **SAR Duty owns it.** It is not D4H data and nothing about it goes to D4H. Teams on D4H
  and on SAR Duty Records work the same.
- **Dates, not jobs.** [MemberAwayPeriod](../lib/app/model/member_away_period.ex) stores
  a first and last day on the team's clock and a short reason the team admin writes,
  such as "Parental leave", and `MemberAwayPeriod.standing/3` works out standing when
  read. No job flips a member back.
- **The reason is free text, not a list** (decided 2026-10-18). A fixed list of
  categories guessed at teams' cases and nothing read it. The hint asks for no medical
  details.
- **Not a person** is the old toggle, unchanged in `members.not_a_person`. It wins over
  an away period. **Active** is the absence of both and is never stored.
- The member's **Standing** tab lists away periods, past ones too, with a form to add one
  and buttons to end one today or delete it. Any team admin can. The sidebar on every
  member tab shows the standing. Each change goes in the member's history, from
  `member_standing_changes`, which keeps the reason and dates.
- Members do not see their standing, and the reason is `redact: true`.

Nothing leaves a group or a list for standing unless a rule written on its page says so.
These stay as they were, since a bot cannot attend or be invited, and skip members
marked not a person with no rule: invites (`InviteGroups`), the home page's counts and
charts, the missing details filter, and the attendance list at the door.

## Member logins

A team admin turns on member logins in **Settings → Member logins**, in the team area. Then every
current member of the team can log in with the email or mobile number D4H has for them,
and land on their own page, `/teams/:subdomain/me`
([MeLive](../lib/web/live/me_live.ex)). It shows the ID card a team admin issued them,
with the Wallet buttons, their tax credit letters as PDFs, their hours and activities for a
year, and their qualifications. On `/teams/:subdomain/me/details` they change their
mailing address and emergency contacts in D4H, and on `/teams/:subdomain/me/mobile` their
mobile number. Members don't change their email: teams keep it consistent, and team
admins change it in D4H. Issue #156 has the design.

### What must stay true

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
- **Member pages are outside the team pages' `live_session`.** They set `member`, which
  puts them in the member area ([navigation.md](navigation.md)), and never set
  `current_team`. A team admin is a member too, and switches to their member area from
  the account menu.
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

# Writing for SAR Duty

The rules for every word a person reads in SAR Duty: pages, buttons, labels, hints, errors,
flash messages, emails, PDFs, and wallet passes. Agents follow them when they write or
change any of that text. They do not cover code comments, commit messages, or docs.

Check new or changed text against [the checklist](#checklist) before you commit.

## Who reads it

Search and rescue team managers and members. They are volunteers, often tired, sometimes
reading on a phone at a trailhead, and not all of them read English first. They want to
finish a task and leave. Write so a reader understands each sentence the first time.

## Rules

1. **Put what matters first.** The result or the action, then the reason. "Attendance
   cannot be changed. The activity is published in D4H." Not "Because the activity is
   published in D4H, …".
2. **Keep sentences short.** At most 20 words in instructions, warnings, and errors, and 25
   anywhere else. If a sentence needs "and" twice, split it.
3. **One instruction per sentence.** Steps are a numbered list with one action each.
4. **Use the active voice and say who acts.** "SAR Duty refreshes from D4H every night",
   not "Data is refreshed nightly". Instructions use the imperative: "Paste the report".
5. **Use the words in [the glossary](#glossary), every time.** One word for one thing, and
   one meaning for each word. Never switch to a synonym for variety.
6. **Use common words.** Write "use", "before", "to", and "about", not "utilize", "prior
   to", "in order to", and "regarding". [Words to avoid](#words-to-avoid) lists more.
7. **Write negatives in full in instructions, warnings, and errors**: "cannot", "do not",
   "is not". People skimming misread "can't" and "don't" as their opposite, and there a
   misread "not" leads them to do the wrong thing. Elsewhere a negative contraction is fine
   when its meaning cannot flip, such as a button beside its opposite: "I'll be there" and
   "Can't make it". Positive contractions such as "you'll" and "it's" are fine anywhere.
8. **Use sentence case everywhere.** Headings, page titles, buttons, labels, tabs, and
   menu items: "Create letter", "Tax credit letters", "Change password". Proper nouns keep
   their capitals: D4H, SAR Duty, SARVAC, Apple Wallet.
9. **Write numbers as digits**, including one to nine: "3 changes", "1 member". Use
   `Service.Format.count/2` so the noun agrees with the number.
10. **Every value people read comes from a `Service.Format` function.** Never write a
    number and its unit by hand, such as `{days} days`; a test fails if you do. Add a
    function to `Service.Format` when none fits, so a value reads the same everywhere and
    changes in one place. Work the number out with `Service.Convert`, such as
    `days_until/2`, which rounds up. Dates put the month first: "Sep 28, 2025", or
    "September 28, 2025" in letters. Times use the 24-hour clock ("14:05"). A time follows
    its date after a comma: "Oct 21, 14:05", "Oct 21, 2026, 14:05". Durations come from
    `duration/1`: "212h 30m", "202 hours" with no minutes, "1 hour", and "45 min" under an
    hour. Never "212:30" or "212.5 hours". Days come from `days/1` ("30 days"), distances
    from `km/1` ("42 km"). The style guide's Values page, `/styles/values`, runs every
    formatter on an example.
11. **Talk to the reader as "you".** Say "your team" and "your D4H access key". Use "we"
    only for SAR Duty the service, and rarely. The two reply buttons are the exception:
    they speak for the member.
12. **Be plain, not cheerful.** No "please", "sorry", "oops", "simply", "just", "easily",
    exclamation marks, or jokes. Say what happened and what to do next.
13. **Never blame the reader.** "Enter a date", not "You entered an invalid date".
14. **No Latin abbreviations or symbols for words.** Write "for example", not "e.g.", and
    "and", not "&". Do not end a list with "etc."; list everything or say "such as".
15. **Use Canadian spelling in text people read**: colour, centre, kilometre, licence (the
    noun), cheque, defence, catalogue, travelled. Keep "-ize" endings: organize, authorize.
    Code stays in US spelling: identifiers, CSS classes and tokens, routes, comments, and
    commit messages say `color`, not `colour`.

## Patterns

**Buttons.** A verb and its object, three words or fewer, saying what happens: "Create
letter", "Save settings", "Perform 3 changes". Never "Submit", "OK", "Yes", "Go", or
"Click here". The button that confirms a delete names the thing: "Delete endorsement".
The two replies to an invitation are the exception: see Replies in [Patterns](#patterns).

**Links.** The link text says where it goes and makes sense out of context: "tax credit
letters for 2025". Never "here", "click here", "more", or "this page".

**Labels.** A short noun phrase with no colon: "Mailing address". Mark optional fields with
"(optional)" after the label. Do not mark required fields.

**Hints.** One or two short sentences under the label. Give an example of the format:
"Latitude and longitude, like 49.75533, -123.13110."

**Error messages.** Say how to fix it, starting with the verb: "Enter who authorizes tax
letters", "Select a year", "Phone must be 10 digits". Never "invalid", "error", "failed",
or "something went wrong" alone. The message in the error summary and on the field is the
same text.

**Success messages.** What changed, in the past tense, with the count: "4 attendance
changes saved to D4H". No "successfully".

**Confirmations.** Before a change that cannot be undone, name the thing and what happens:
"Delete First Aid? It comes off ID cards and the rules of Callout." The buttons are the action
("Delete endorsement") and "Cancel".

**Warnings.** The consequence first, then what to do: "Attendance cannot be changed once
the activity is published. Unpublish it in D4H first."

**Empty states.** Say why it is empty and what to do: "No tax credit letters for 2025 yet.
Create one from the member list." Not "No results".

**Slow work.** Name the slow thing: "Refreshing from D4H…", "Calculating driving distances
for 14 members…". Not "Loading…" or "Please wait".

**Page titles.** The same words as the page's `h1`. The browser title adds " · SAR Duty".

**Replies.** A member answers an invitation with two buttons in their own voice: "I'll be
there", the success button, and "Can't make it". These are the only buttons that speak for
the reader. Once they answer, the buttons give way to their reply, "Signed up" or "Can't
make it", and a "Change" link. Show nothing about invitations to a member who is not
invited: never "Not invited". Replies close when the activity starts.

## Invitations and attendance

D4H keeps an attendance row for each member invited to an activity. Name its status with
these words, which change when the activity starts:

| D4H status | Before it starts | Once it starts |
| ---------- | ---------------- | -------------- |
| Requested  | No reply         | No reply       |
| Attending  | Signed up        | Attended       |
| Absent     | Can't make it    | Absent         |

Only `Attendance.attended/2` makes a member attended. "Absent" is only for an activity that
has started, such as a no-show the door marks. Never call a reply "absent", and never call a
member who signed up "attending".

Where the words go:

- **A count in a list or a card:** "23 signed up" before it starts, "23 attended" once it
  starts. `Service.Format.count/2` makes "1 signed up" and "0 signed up".
- **A heading over names:** the state, a middle dot, and the count. Before it starts:
  "Signed up · 23", "Can't make it · 4", "No reply · 31". Once it starts: "Attended · 23"
  and "Absent · 4". Leave out a heading with nobody under it, except the first.
- **Nobody yet:** "Nobody has signed up yet." and "Nobody attended."
- **The member's own row:** "You're invited." and the two buttons. After they answer, "Signed
  up" with a check mark or "Can't make it", then "Change". "Add to calendar" follows "Signed
  up" where there is room.
- **Invitations the member has not replied to:** a count in Coming up's header on the
  Dashboard, such as "2 waiting for your reply". The Activities menu's count stays the team
  admin's proposed changes.
- **The door:** "Yet to arrive", with "3 of 9 signed up".
- **An ask by email or text:** the activity, its day and time, and "Will you be there?",
  with the same two buttons.
- **After a reply:** in SAR Duty the row changes in place, with no flash message. From an
  email, the page says "Signed up for Training night, Thursday Oct 29 at 19:00." with "Add
  to calendar", or "Your reply: Can't make it."

## Glossary

Use the term in the first column. The second column lists words that mean the same thing
and must not be used for it.

| Use                            | Not                                            | Meaning                                                                                              |
| ------------------------------ | ---------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| SAR Duty                       | SARDuty, Sar Duty, the app, the system         | This service.                                                                                        |
| D4H                            | d4h, D4H Decisions, D4H Technologies           | The team's system of record.                                                                         |
| SAR Duty Records               | the store, hosted D4H, Records app             | Where a team without D4H keeps its records. "Records" alone only after the full name on the page.    |
| team                           | organization, unit, group, chapter             | A search and rescue team using SAR Duty.                                                             |
| member                         | user, responder, volunteer, person, personnel  | A person on the team's D4H roster.                                                                   |
| account                        | user, login, profile                           | What a person logs in to SAR Duty with.                                                              |
| your membership                | member area, your details, profile, my page    | A member's own page on one team: their activities, qualifications, ID card, letters, and details.    |
| account settings               | your settings, profile, preferences            | The page for your own login and settings, the same on every team, such as your maps app.             |
| team settings                  | settings (alone, in the menu), admin settings  | A team's settings, for its team admins: General, Team admins, Member logins, and more.               |
| team admin                     | administrator, owner, manager, superuser       | A person who can change the team's settings.                                                         |
| member logins                  | member portal, self-service, member access     | A team's setting that lets current members log in for their own ID card and tax credit letters.      |
| activity                       | event, callout, mission, task, deployment      | Anything in D4H that members attend. There are three kinds.                                          |
| incident                       | callout, call-out, mission, search, task       | An activity responding to a call.                                                                    |
| exercise                       | training, practice, drill                      | An activity for training.                                                                            |
| event                          | meeting, function                              | An activity that is neither, such as a meeting. Never use "event" for activities in general.         |
| attendance                     | participation, roll call                       | Which members attended an activity, and for how long.                                                |
| attended                       | present, participated                          | A member's state on an activity's attendance.                                                        |
| published                      | locked, closed, finalized                      | An activity out of draft in D4H. D4H doesn't let SAR Duty change its tags.                           |
| qualification                  | certification, cert, ticket, course, skill     | Something a member holds in D4H, such as a first aid course. It can expire.                          |
| certificate                    | proof, card, qualification                     | The paper or PDF proof of a course, which a team admin records in D4H as a qualification.            |
| group                          | team, squad, list, role                        | A D4H group of members.                                                                              |
| group rule                     | requirement, policy, criteria                  | One thing a member must meet to be in a group: in or not in groups or endorsements, or a standing.   |
| endorsement                    | clause, credential, rating, skill set          | A name and the qualifications that earn it, such as First Aid. Holding any one of them earns it.     |
| primary hours, secondary hours | main hours, other hours, type 1, type 2        | Hours as SARVAC counts them for the tax credit.                                                      |
| tax credit letter              | TCL, tax letter, tax receipt, certificate      | The PDF letter a member gives the CRA. Say "letter" alone only after the full term on the same page. |
| category                       | kind, type                                     | D4H's grouping of items, such as Radio. Not an item's type, and not a chore category.                |
| chore                          | task, job, duty, volunteer hours               | Time a member gives the team outside activities, such as fixing equipment, logged by them.           |
| chore category                 | chore type, chore kind                         | What a chore counts as, such as Equipment maintenance. Each send gives it a D4H activity per year.   |
| accepted, declined             | approved, rejected, counted                    | A team admin's answer on a chore. "Approved" is D4H's word for activities.                           |
| equipment                      | gear, assets, inventory                        | What a team owns and logs in D4H: vehicles, radios, supplies.                                        |
| item                           | asset, piece, unit                             | One piece of equipment in D4H. A truck is an item, and so is a drawer in it.                         |
| template                       | kit, preset, bundle, set                       | SAR Duty's named set of items, tags, and groups to invite, applied to an activity in one step.       |
| mileage report                 | distance report, travel claim, kilometres      | Driving distances to an activity, in km.                                                             |
| ID card                        | member card, pass, badge, ID                   | A member's card in Apple Wallet or Google Wallet. Say "Wallet" only when naming where it lives.      |
| verify                         | check, validate, scan                          | Confirming an ID card or a tax credit letter is real.                                                |
| D4H access key                 | token, API key, personal access token, PAT     | The key that lets SAR Duty read and change the team's D4H data.                                      |
| Records access key             | token, API key                                 | The same for a team on SAR Duty Records. Records' own page for them is "API keys".                   |
| MCP token                      | API key, access key, agent key                 | A team admin's own token that lets their AI agent read the team's data in SAR Duty.                  |
| refresh                        | sync, update, import, pull, fetch              | Copying the team's data from D4H or SAR Duty Records into SAR Duty.                                  |
| attendance link                | sign-in link, check-in link, door link         | The link a team admin makes so someone at the door can take attendance for one activity.             |
| arrived, left                  | signed in, signed out, checked in, checked out | A member's scans at the door. "Arriving" and "Leaving" are the modes on the door's page.             |
| check-in, checked in           | contact, follow-up, call log                   | A team admin's record that they reached a member. Never a scan at the door: that is "arrived".       |
| standing                       | status, availability, state                    | Active, Away, Not a person, or Retired. "Status" is D4H's member status.                             |
| retired                        | departed, left the team, former, inactive      | A member no longer on the team: D4H retired them or no longer lists them. D4H's own word.            |
| not retired                    | current (as a filter)                          | The Standing filter's default: Active, Away, and Not a person. All adds the retired.                 |
| away period                    | LOA, absence                                   | Dated time a member is away, with a short reason such as "Parental leave".                           |
| no-show                        | absentee, missing member, did not attend       | A member who signed up for an activity and did not arrive.                                           |
| signed up for                  | registered, going, coming, attending, RSVP     | A member's yes to an activity that hasn't started: Attending in D4H. Hours count once it starts.     |
| invite                         | request, ask, call out                         | Asking a member to come to an activity. They show as "No reply" until they answer.                   |
| reply                          | RSVP, response, answer                         | A member's answer to an invitation: "I'll be there" or "Can't make it".                              |
| can't make it                  | absent, declined, can't go, not going          | A member's no to an activity that hasn't started: Absent in D4H.                                     |
| no reply                       | unconfirmed, pending, requested                | Invited, with no answer yet: Requested in D4H.                                                       |
| absent                         | can't make it, missing                         | D4H's status for a member who did not come to an activity that has started.                          |
| log in, log out                | sign in, sign out, login (as a verb), logon    | Starting and ending a session. "Log in" is the verb and the button.                                  |
| sign up                        | register, create account, signup (as a verb)   | Making a new account.                                                                                |
| email                          | e-mail, mail, email address (as a label)       | The label is "Email".                                                                                |
| time zone                      | timezone, TZ                                   | Two words in text and labels.                                                                        |
| latitude, longitude            | lat, lng, long, coordinates                    | Spelled out in labels.                                                                               |
| km                             | KMs, kms, kilometres                           | Distances, after a number with a space: "42 km".                                                     |
| select                         | click, tap, press, choose, pick                | What the reader does to a button, link, or option.                                                   |

## Words to avoid

| Avoid                         | Write                                    |
| ----------------------------- | ---------------------------------------- |
| click, tap, hit, press        | select                                   |
| submit                        | the specific action: save, send, create  |
| invalid, error, failed        | what is wrong and how to fix it          |
| please, kindly, sorry, oops   | nothing                                  |
| simply, just, easily, quickly | nothing                                  |
| successfully                  | nothing                                  |
| utilize, leverage             | use                                      |
| in order to                   | to                                       |
| prior to, subsequent to       | before, after                            |
| ensure                        | make sure                                |
| via                           | through, by, with                        |
| e.g., i.e., etc.              | for example, that is, or list everything |
| and/or                        | or                                       |
| sync                          | refresh                                  |
| N/A                           | "None", or leave the cell empty          |

## Checklist

Before committing text a person will read, check each line:

- [ ] The result or action comes first.
- [ ] No sentence is over 20 words in an instruction, warning, or error, or over 25
      elsewhere.
- [ ] Every term matches [the glossary](#glossary), and nothing from its "Not" column is
      used.
- [ ] Nothing from [words to avoid](#words-to-avoid) is used.
- [ ] Negatives are in full in instructions, warnings, and errors: "cannot", "do not".
- [ ] Headings, titles, buttons, labels, and tabs are in sentence case.
- [ ] Buttons are a verb and an object, except the two replies. Links make sense on
      their own.
- [ ] Invitations and attendance use [their words](#invitations-and-attendance), switching
      when the activity starts.
- [ ] Errors say how to fix the problem and match the error summary.
- [ ] Numbers are digits. Every date, time, duration, count of days, and distance comes
      from a `Service.Format` function.
- [ ] Text people read uses Canadian spelling. Code uses US spelling.

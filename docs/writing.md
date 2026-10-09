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
7. **Write negatives in full.** "cannot", "do not", "is not". People misread "can't" and
   "don't" as their opposite when they skim. Positive contractions such as "you'll" and
   "it's" are fine.
8. **Use sentence case everywhere.** Headings, page titles, buttons, labels, tabs, and
   menu items: "Create letter", "Tax credit letters", "Change password". Proper nouns keep
   their capitals: D4H, SAR Duty, SARVAC, Apple Wallet.
9. **Write numbers as digits**, including one to nine: "3 changes", "1 member". Use
   `Service.Format.count/2` so the noun agrees with the number.
10. **Format dates, times, and durations with `Service.Format`.** Never build them by hand.
    Dates put the month first: "Sep 28, 2025", or "September 28, 2025" in letters. Times use
    the 24-hour clock ("14:05"). Durations are hours and minutes ("212h 30m"). Distances are
    in km.
11. **Talk to the reader as "you".** Say "your team" and "your D4H access key". Use "we"
    only for SAR Duty the service, and rarely.
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
"Click here". The button that confirms a delete names the thing: "Delete clause".

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
"Delete the First Aid clause and its 3 qualifications?" The buttons are the action
("Delete clause") and "Cancel".

**Warnings.** The consequence first, then what to do: "Attendance cannot be changed once
the activity is published. Unpublish it in D4H first."

**Empty states.** Say why it is empty and what to do: "No tax credit letters for 2025 yet.
Create one from the member list." Not "No results".

**Slow work.** Name the slow thing: "Refreshing from D4H…", "Calculating driving distances
for 14 members…". Not "Loading…" or "Please wait".

**Page titles.** The same words as the page's `h1`. The browser title adds " · SAR Duty".

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
| team admin                     | administrator, owner, manager, superuser       | A person who can change the team's settings.                                                         |
| activity                       | event, callout, mission, task, deployment      | Anything in D4H that members attend. There are three kinds.                                          |
| incident                       | callout, call-out, mission, search, task       | An activity responding to a call.                                                                    |
| exercise                       | training, practice, drill                      | An activity for training.                                                                            |
| event                          | meeting, function                              | An activity that is neither, such as a meeting. Never use "event" for activities in general.         |
| attendance                     | participation, roll call, check-in             | Which members attended an activity, and for how long.                                                |
| attended                       | present, participated                          | A member's state on an activity's attendance.                                                        |
| published                      | locked, closed, finalized                      | An activity whose attendance D4H no longer lets anyone change.                                       |
| qualification                  | certification, cert, ticket, course, skill     | Something a member holds in D4H, such as a first aid course. It can expire.                          |
| group                          | team, squad, list, role                        | A D4H group of members.                                                                              |
| group rule                     | requirement, policy, criteria                  | The qualifications a member must hold to be in a group.                                              |
| clause                         | condition, line, requirement                   | One part of a group rule: the member must hold any of its qualifications.                            |
| primary hours, secondary hours | main hours, other hours, type 1, type 2        | Hours as SARVAC counts them for the tax credit.                                                      |
| tax credit letter              | TCL, tax letter, tax receipt, certificate      | The PDF letter a member gives the CRA. Say "letter" alone only after the full term on the same page. |
| mileage report                 | distance report, travel claim, kilometres      | Driving distances to an activity, in km.                                                             |
| ID card                        | member card, pass, badge, ID                   | A member's card in Apple Wallet or Google Wallet. Say "Wallet" only when naming where it lives.      |
| verify                         | check, validate, scan                          | Confirming an ID card or a tax credit letter is real.                                                |
| D4H access key                 | token, API key, personal access token, PAT     | The key that lets SAR Duty read and change the team's D4H data.                                      |
| Records access key             | token, API key                                 | The same for a team on SAR Duty Records. Records' own page for them is "API keys".                   |
| MCP token                      | API key, access key, agent key                 | A team admin's own token that lets their AI agent read the team's data in SAR Duty.                  |
| refresh                        | sync, update, import, pull, fetch              | Copying the team's data from D4H or SAR Duty Records into SAR Duty.                                  |
| attendance link                | sign-in link, check-in link, door link         | The link a team admin makes so someone at the door can take attendance for one activity.             |
| arrived, left                  | signed in, signed out, checked in, checked out | A member's scans at the door. "Arriving" and "Leaving" are the modes on the door's page.             |
| no-show                        | absentee, missing member, did not attend       | A member who signed up for an activity and did not arrive.                                           |
| import attendance              | upload, sync attendance                        | Reading a SAR Assist attendance report to change D4H attendance.                                     |
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
- [ ] Negatives are in full: "cannot", "do not".
- [ ] Headings, titles, buttons, labels, and tabs are in sentence case.
- [ ] Buttons are a verb and an object. Links make sense on their own.
- [ ] Errors say how to fix the problem and match the error summary.
- [ ] Numbers are digits. Dates, times, and durations come from `Service.Format`.
- [ ] Text people read uses Canadian spelling. Code uses US spelling.

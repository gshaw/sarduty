# Search

<!-- cspell:ignore exqlite -->

The search in the top bar (#473) finds a team's members, activities, equipment,
qualifications, groups, endorsements, templates, and pages by name, D4H number, or
barcode, chores by what the member wrote, and certificates by their qualification or
member. [App.ViewData.Search](../lib/app/view_data/search.ex) matches and ranks;
[Web.Search](../lib/web/search.ex) decides what the person searching may find and where
each result opens.

## No index

Search reads the live tables on every search. The largest team has about 3,600 activities
and 400 members, and a LIKE over all its activities takes a few ms. With no index there is
nothing to keep in step, so a refresh from D4H or a record added in SAR Duty is found on
the next keystroke.

Move to SQLite FTS5 if a team passes about 50,000 rows, or for typo tolerance. exqlite,
the SQLite driver, builds SQLite with FTS5. Keep the index current with triggers, not Ecto
callbacks, so every write path updates it, including the refresh's bulk writes.

## Matching and ranking

- **Every word must match, in any order**, each in one of the kind's fields: a name or
  title, a D4H number, a tracking number, a barcode, or a serial. A leading `#` is dropped,
  and `%` and `_` match themselves.
- **Not searched:** email, phone, address, emergency contacts, positions, letter text, and
  activity descriptions.
- **Ranking**, in `score/3`: a D4H number or barcode that is the whole search first (#02193
  finds 2193), then the title is the search, starts with it, has a word starting with each
  word, or holds each word. Ties put current members before retired ones, the activities
  nearest today first, equipment in service first, and the newest chores first.
- Each kind shows its best 5. Groups are ordered by their best result.

## Who finds what

Each kind opens one page, listed in `Web.Search.live_views/0`, and that page's `access`
decides who finds it, by the same rule as the team pages' hook (`UserAuth.opens?/3`). A
member who logs in finds activities; a team admin finds every kind. Chores are found only
on a team with chores on (`Team.chores?/1`), as their pages open only there, and
certificates only on a team with them on (`Team.certificates?/1`).

Pages come from the side navigation the person sees, from `Web.Navigation.sections/3`, so
a page added there is found with no change here. `Web.Search` adds Team admins for team
admins, where they pick the team contacts (#780). A page matches only where a word of its name starts, so "ali" finds
Alice but not Qualifications, or where one of the link's other `words` starts: help, support,
contact, question, problem, bug, and feedback find Get help, and contacts finds Team
admins. Never "admin", which team admins search for the admin pages, or "report", which
is for reports (#768).

## Recent picks

Before you type, search lists the last 5 results you opened on the team. The browser keeps
them in local storage as `"kind:id"` keys, under a name with your user id and the team's
subdomain, so a shared iPad doesn't show the last person's picks. On each page the hook
sends them to the server, and `Web.Search.recent/3` shows only the ones you can still
open. Nothing is stored on the server.

## A new kind of record

Every team page for one record, `/teams/:subdomain/…/:id`, must be a kind in
`Web.Search.live_views/0` or be in `Web.Search.not_searched/0` with a reason.
[test/web/search_test.exs](../test/web/search_test.exs) fails until one of them says so.

To add a kind: its candidates and fields in `App.ViewData.Search`, its page in
`live_views/0`, its path in `hit_path/3`, and an "All …" list in `more_path/3` if the list
takes `?q=`.

## The style guide's search

`/styles` has the same search in its top bar, logged in or not, finding the guide's pages
and their sections instead of a team's records.
[Web.StyleGuideSearch](../lib/web/style_guide_search.ex) builds its index; nobody writes
it.

- **Pages** come from `Web.StyleGuideHTML.groups/0`, the list behind the side
  navigation, and a test fails when a template in `style_guide_html/pages/` is missing
  from it.
- **Text** is each page rendered from its template, as the browser gets it, split at
  every `h2` and `h3` outside an example (`.demo` or `.example`). An entry is the page
  title, the section's heading, and its text, including what the examples print. Nothing
  is copied, so the index says what the pages say.
- **Built** on the first search and kept in `:persistent_term` until the next deploy,
  which is when the pages change. Development builds it on every search, so an edit shows
  at once. A build takes about 50 ms, and 120 ms the first time after a boot; a search
  takes 1 to 3 ms.
- **Ranking:** a page title first, then a section heading, then the text, each word
  matching where a word starts. A result opens its section with a text fragment
  (`/styles/phone#:~:text=When%20not%20to%20use`), so headings need no ids; when the
  heading's words show earlier on the page, the words after it are added to pick the
  right one. A browser without text fragments opens the page at the top.
- **Wiring:** the guide's pages are controller-rendered, so its frame `live_render`s
  `Web.StyleGuideSearchLive`, and `assets/js/styles.js` connects it with the app's
  `Search` hook. The results are `Web.Components.Search`'s markup, the team search's.
  Recent picks are kept in the browser under `sarduty:styles-search-recent`.

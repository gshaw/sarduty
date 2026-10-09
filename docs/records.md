# SAR Duty Records

Some teams do not use D4H. Their records live in SAR Duty Records, a separate app at
<https://records.sarduty.com> (private repo `gshaw/sarduty-records`). Records serves
D4H's v3 API shape at `https://records.sarduty.com/v3/team/<id>/…`, so SAR Duty treats
it as one more place a team's records live. The refresh, the sync, change sets, and
every page work the same for both.

Why a separate app rather than a store inside SAR Duty (2026-10-08): SAR Duty keeps one
job, copying a team's records and building on them, and Records can grow its own logins
and approval without touching SAR Duty. The old in-app store (#252–#257) was closed for
this.

## How a team connects

1. A team admin signs the team up in Records, and a Records admin approves it.
2. On the team's API keys page in Records, they create a key, such as "SAR Duty".
3. At SAR Duty's sign-up, they choose **SAR Duty Records** under "Where your team's
   records are", and paste the key.

Sign-up then runs as for a D4H team: `whoami`, the team, and its members come from
Records, and the person signing up must be an Owner or Editor there. The team's
`d4h_api_host` is Records' host, and its key is stored encrypted in `d4h_access_key`
like a D4H key. Existing D4H teams need no change.

## The service check

- `D4H.services/0` is the approved list: each D4H region, then SAR Duty Records. Sign-up
  validates against it, and SAR Duty never calls a host off it. There is no free URL.
- `D4H.service/1` says `:d4h` or `:records` for a team or a host, and `D4H.records?/1`
  is the short form. `D4H.service_name/1` and `D4H.key_name/1` give the words people
  read: "SAR Duty Records" and "Records access key".
- A Records team sees no "Open D4H" links. Text that names where the records are, such as
  the team home's refresh line, Needs attention, and team settings, names Records.
- `D4H.records_host/0` is `records.sarduty.com`. In dev, `RECORDS_HOST` points it at a
  local copy.

## Where the code is

- [App.Adapter.D4H](../lib/app/adapter/d4h.ex) calls Records exactly as it calls D4H,
  over HTTPS with the team's bearer key.
- Records' side is documented in its repo, in `Docs/api.md`.

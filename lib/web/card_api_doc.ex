defmodule Web.CardApiDoc do
  @moduledoc """
  How to check an ID card as JSON: the text of /agents/id-cards (Web.CardApiLive) and
  /agents/id-cards.md (Web.MarkdownController). Web.CardApiController is what it
  describes; keep the two in step.
  """

  @doc "The page as Markdown, with this site's verify host in every example."
  def markdown do
    verify = Web.VerifyHost.url()

    """
    # How to check an ID card

    Every SAR Duty ID card has a QR code that opens the card's page on the verify site, such as `#{verify}/K7Q4-M2XA`. An app that signs members in, such as SAR Command Assist, can ask the same check as JSON: scan the card, take the code, and get back who it is, their team, and whether they are an active member.

    Try it on a sample card, which is a made-up member of Coast Range SAR: [#{verify}/api/cards/SAMP-ACTV](#{verify}/api/cards/SAMP-ACTV).

    ## Get the code from a scan

    The QR code holds a link like `HTTPS://VERIFY.SARDUTY.COM/K7Q4-M2XA`, in capitals. The code is the last part of the link. Check that the link's host is `#{Web.VerifyHost.host()}` before you take the code: a card whose QR code opens any other site is not a SAR Duty card.

    Codes are 8 letters and numbers, printed under the QR code with a dash in the middle. The check takes them with or without the dash, in either case.

    ## Ask for the card

    ```
    GET #{verify}/api/cards/K7Q4-M2XA
    ```

    No key or login. It answers what the verify page shows anyone who has the card in hand, and nothing more.

    ## What comes back

    An active member's card:

    ```json
    {
      "code": "K7Q4-M2XA",
      "status": "active",
      "sample": false,
      "member": {
        "name": "Cameron Ruiz",
        "joined_at": "2023-10-31T03:06:10Z",
        "photo_url": "#{verify}/K7Q4-M2XA/photo",
        "qualifications": [
          {"name": "First aid", "ends_at": "2027-11-18T12:00:00Z"},
          {"name": "Ground search and rescue", "ends_at": null}
        ]
      },
      "team": {
        "name": "Coast Range SAR",
        "organization": null,
        "refreshed_at": "2026-11-04T03:06:10Z",
        "valid_until": "2027-03-01T06:59:59Z"
      },
      "records": {
        "service": "d4h",
        "api_url": "https://api.ca.d4h.org",
        "team_id": 9100000,
        "member_id": 9110132
      }
    }
    ```

    - `status` is `active`, `inactive` (the member left the team), or `revoked` (the team cancelled or replaced the card). Sign in only an `active` card.
    - `sample` is true for Coast Range SAR's made-up cards. Never accept one as ID.
    - `photo_url` is the member's photo, a square PNG. Show it, and compare it with the person: the photo is what a copied code can't fake.
    - `qualifications` are the ones the team lists on its cards. `ends_at` is null when one doesn't expire.
    - `refreshed_at` is when SAR Duty last copied the team's records, so a status can be that far behind.
    - Times are ISO 8601, in UTC. `joined_at` and `organization` can be null.

    A former member's card gives only `member.name` and `member.left_at`: no photo and no qualifications. A revoked card gives only `code`, `status`, and `sample`.

    A code that matches no card is a `404` with `{"status": "not_found"}`.

    ## Too many misses

    20 codes that match no card in 10 minutes from one IP address, on this check or the verify page, and that address gets `429` with `{"status": "limited"}` for a while. Real cards never count, so checking a crowd at a callout can't trip it.

    ## More about the member

    `records` says where the team keeps its records: `service` is `d4h` for D4H Team Manager, or `records` for SAR Duty Records. Both serve D4H's v3 API at `api_url`, so the member is at:

    ```
    GET {api_url}/v3/team/{team_id}/members/{member_id}
    ```

    That needs an access key from the member's own team, from D4H or from SAR Duty Records. Without one, the IDs open nothing. Use them to match a scanned card to a member your app already has from that team.

    ## Matching members you already have

    Match on `records.team_id` and `records.member_id`, not the name or the team's own ID number. Two teams can give out the same ID number, and a member keeps the same D4H ID when their card is replaced. The card's code changes when the team issues a new card, so don't store it as the member's ID.
    """
  end
end

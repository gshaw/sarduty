defmodule Web.CardApiDoc do
  @moduledoc """
  How to check an ID card as JSON: the text of /agents/id-cards (Web.CardApiLive) and
  /agents/id-cards.md (Web.MarkdownController). Web.CardApiController is what it
  describes; keep the two in step. Web.CardApiLiveTest checks the example's fields
  against a real answer.
  """

  @doc "The page as Markdown, with this site's verify host in every example."
  def markdown do
    verify = Web.VerifyHost.url()

    """
    # How to check an ID card

    Every SAR Duty ID card has a QR code that opens the card's page on the verify site, such as `#{verify}/K7Q4-M2XA`. An app that signs members in, such as SAR Command Assist, can ask SAR Duty the same check as JSON: scan the card, take the code, and get back who it is, their team, and whether they are an active member.

    Try it on a sample card, a made-up member of Coast Range SAR: [#{verify}/api/v1/cards/SAMP-ACTV](#{verify}/api/v1/cards/SAMP-ACTV).

    ## Get the code from a scan

    The QR code holds a link like `HTTPS://VERIFY.SARDUTY.COM/K7Q4-M2XA`, in capitals. The code is the last part of the link. Don't open the link: send the code to the address below, whatever site the link names. A forged card can't send your app anywhere else that way.

    Codes are 8 letters and numbers, printed under the QR code with a dash in the middle. The check takes them with or without the dash, in either case.

    ## Ask for the card

    ```
    GET #{verify}/api/v1/cards/K7Q4-M2XA
    ```

    No key or login. It answers what the verify page shows anyone who has the card in hand, plus where an active member's records live.

    Read the answer here, not the card's page. The page answers `200` for every code, even one that matches no card.

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

    - `status` is `active`, `inactive` (the member left the team), or `revoked` (the team cancelled or replaced the card). All three answer `200`, so read `status`, not the HTTP code. Sign in only an `active` card.
    - `sample` is true for Coast Range SAR's made-up cards. Never accept one as ID.
    - `photo_url` is the member's photo, a square PNG. Show it, and compare it with the person: the photo is what a copied code can't fake.
    - `qualifications` are the ones the team lists on its cards. `ends_at` is null when one doesn't expire.
    - `refreshed_at` is when SAR Duty last copied the team's records, so a status can be that far behind.
    - Times are ISO 8601, in UTC, to the second. `joined_at` and `organization` can be null.

    A former member's card gives `member.name`, `member.left_at`, and `team`: no photo, no qualifications, and no `records`. `left_at` is null when the team marked them retired without a date.

    A revoked card gives only `code`, `status`, and `sample`.

    A code that matches no card answers `404` with `{"status": "not_found"}`.

    New fields can appear in any answer, so ignore the ones you don't know. A change that would break an app gets a new address, `/api/v2`.

    ## Too many misses

    20 codes that match no card in 10 minutes from one IP address, here or on the verify page, and that address gets `429` with `{"status": "limited"}` and a `Retry-After` header, for up to 10 minutes.

    Only codes that could be a card's count. Real cards never count, and nor does anything else your scanner reads, such as another app's QR code. So checking a crowd at a callout can't trip it, even though everyone at a command post shares one address.

    ## No internet

    The check needs SAR Duty, and a command post may have no internet. Keep each answer by its code, so a code you've checked before can sign its member in from your saved answer. For a new code, record the scan and the time, check it once you're back online, and flag any that come back not `active`.

    ## More about the member

    `records` says where the team keeps its records: `service` is `d4h` for D4H Team Manager or `sar_duty_records` for SAR Duty Records, and more may come. Both serve D4H's v3 API at `api_url`, so the member is at:

    ```
    GET {api_url}/v3/team/{team_id}/members/{member_id}
    ```

    That needs an access key from the member's own team, from D4H or from SAR Duty Records. Without one, the IDs open nothing.

    ## Matching members you already have

    Match on `api_url`, `team_id`, and `member_id` together: a member ID alone can repeat between D4H and SAR Duty Records. Don't match on the name or the team's own ID number, which two teams can share. A member keeps their IDs when their card is replaced, but the card's code changes, so don't store the code as the member's ID.
    """
  end
end

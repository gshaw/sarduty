defmodule Web.DemoAgentsDoc do
  @moduledoc """
  How an agent starts a demo and shows someone SAR Duty: the text of /agents/demo
  (Web.DemoAgentsLive) and /agents/demo.md (Web.MarkdownController). Web.DemoApiController
  and Web.DemoController are what it describes; keep them in step.
  """

  alias App.Model.DemoTeam

  @doc "The page as Markdown, with this site's address in every example."
  def markdown do
    url = Web.Endpoint.url()
    days = Service.Format.count(DemoTeam.days(), one: "%d day", many: "%d days")

    """
    # How to show someone SAR Duty

    Someone new to SAR Duty can ask an agent to show them what it does, or whether it has a feature they need. The agent starts a demo: a made-up search and rescue team, Coast Range SAR, of their own for #{days}. It opens the demo in a browser, goes to the pages that answer the question, tries things, and gives the person the demo's link so they can look too.

    A demo sends nothing. Every email it would send, such as an activity's reminders, is kept in its Outbox, where the agent can read it and follow its links as the member would.

    ## Start a demo

    In a browser, open [#{url}/demo](#{url}/demo) and select **Start a demo**. A name is optional: it becomes the person's member on the team.

    Or ask for one:

    ```
    POST #{url}/api/demos
    Content-Type: application/json

    {"name": "Morgan Visitor"}
    ```

    The answer is `201` with the demo's link:

    ```json
    {
      "url": "#{url}/demo/open/SFMyNTY…",
      "kind": "visitor",
      "expires_at": "2026-11-07T19:00:00Z"
    }
    ```

    Opening the link logs the browser in as the demo's team admin and builds the team, which takes a few seconds the first time. The link works for the demo's life, in any browser, so give it to the person you're helping. Anyone with the link can open the demo.

    A connection can start 5 demos an hour. `429` means wait an hour; `503` means demos are full or off for now.

    ## Find your way around

    Every page of a demo has a banner with its link, its Outbox, **View as Cameron Ruiz** to see SAR Duty as a member does, and **Delete this demo**. The side navigation has the rest. The team has a year of activities, members with qualifications and ID cards, equipment, and chores.

    For what a page is for, read its heading and the one-line description under it. SAR Duty's own [Agents](#{url}/agents.md) page lists what else agents can do.

    ## End a demo

    The demo is deleted on its own after #{days}. To delete it sooner, select **Delete this demo** on the banner, or:

    ```
    DELETE #{url}/api/demos/SFMyNTY…
    ```

    with the token from the end of its link. The answer is `204`.

    ## Test demos

    A script that checks SAR Duty on a live server can start a test demo: send `Authorization: Bearer` with SAR Duty's test key, and `"hours"` for how long it lasts, 2 by default and 24 at most. Test demos skip the limits on visitors' demos. Delete each one when the script is done.
    """
  end
end

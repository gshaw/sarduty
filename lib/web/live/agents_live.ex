defmodule Web.AgentsLive do
  use Web, :live_view_marketing_layout

  # How agents work with SAR Duty (#816): public, beside Privacy and Terms, for teams and
  # organizations deciding about agents. Each team's Agents tab and the page that lets an
  # agent in link here. It lists what agents read under /agents, each also as Markdown.
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "How agents work with SAR Duty",
       page_description:
         "How AI agents help team admins write SAR Duty reports from how a team is organized, never its members or records."
     )}
  end

  def render(assigns) do
    ~H"""
    <article id="agents" class="container mx-auto px-2 pt-8">
      <div class="max-w-prose">
        <h1 class="title">How agents work with SAR Duty</h1>
        <p class="lead">
          An AI agent, such as Claude or ChatGPT, can help a team admin write reports. SAR Duty is built so the agent does that without the team's records.
        </p>

        <h2 class="heading mt-8">How it works</h2>
        <ol id="agents-steps" class="list-decimal pl-6">
          <li>
            A team admin asks their agent for a report, such as members on Callout without First Aid.
          </li>
          <li>
            The agent writes it in SAR Duty's <.a navigate={~p"/agents/reports"}>report language</.a>, from the team's saved reports and its names for groups, qualifications, and tags. It tries the report on Coast Range SAR, a made-up team.
          </li>
          <li>The team admin opens the report in SAR Duty. It runs there, on the team's records.</li>
        </ol>

        <h2 class="heading mt-8">What stays in SAR Duty</h2>
        <p id="agents-stays">
          The team's records: its members, activities, and equipment, and the rows of every report. An agent works from how a team is organized, not from who is in it or what they did.
        </p>

        <h2 class="heading mt-8">Who decides</h2>
        <p id="agents-who">
          A team admin connects an agent, and any team admin can disconnect it. Agents never change anything.
        </p>

        <h2 class="heading mt-8">What agents read</h2>
        <ul id="agents-pages">
          <li :for={page <- pages()} id={page.id} class="mb-4">
            <p class="action mb-0"><.a navigate={page.path}>{page.title}</.a></p>
            <p class="mb-0">
              {page.text} Agents read it as Markdown at <.a href={page.markdown}>{Web.Endpoint.host()}{page.markdown}</.a>.
            </p>
          </li>
        </ul>
      </div>
    </article>
    """
  end

  # Each page under /agents, for people and agents alike.
  defp pages do
    [
      %{
        id: "agents-page-reports",
        title: "How to write a report",
        text: "The report language, with an example of each clause.",
        path: ~p"/agents/reports",
        markdown: ~p"/agents/reports.md"
      },
      %{
        id: "agents-page-id-cards",
        title: "How to check an ID card",
        text:
          "The verify site's check as JSON, for apps that sign members in with their ID card.",
        path: ~p"/agents/id-cards",
        markdown: ~p"/agents/id-cards.md"
      }
    ]
  end
end

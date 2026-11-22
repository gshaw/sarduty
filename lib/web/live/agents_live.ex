defmodule Web.AgentsLive do
  use Web, :live_view_marketing_layout

  # The lander for agents (#816): public, beside Privacy and Terms, for teams and
  # organizations deciding about agents, and for agents and the people building with
  # them. AI writing in the report editor links here. Each thing
  # agents can do is one entry in uses/0, linking its page under /agents (`path`) or the
  # public repository (`href`); a new one is an entry there, and shows here and in
  # /agents.md (Web.MarkdownController).
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "How agents work with SAR Duty",
       page_description:
         "What AI agents and the apps built with them can do with SAR Duty, who decides, and what stays with the team."
     )}
  end

  def render(assigns) do
    ~H"""
    <article id="agents" class="page-frame pt-8">
      <div class="max-w-prose">
        <h1 class="title">How agents work with SAR Duty</h1>
        <p class="lead">{lead()}</p>

        <h2 class="heading mt-8">What agents can do</h2>
        <ul id="agents-uses">
          <li :for={use <- uses()} id={use.id} class="mb-6">
            <h3 class="subheading mb-1">{use.title}</h3>
            <p class="mb-1">{use.text}</p>
            <p class="hint mb-1">{use.access}</p>
            <p class="action mb-0">
              <.a :if={use[:path]} navigate={use[:path]}>{use.link}</.a>
              <.a :if={use[:href]} href={use[:href]} external>{use.link}</.a>
            </p>
          </li>
        </ul>

        <h2 class="heading mt-8">What stays in SAR Duty</h2>
        <p id="agents-stays">{stays()}</p>

        <h2 class="heading mt-8">Who decides</h2>
        <p id="agents-who">{who()}</p>

        <h2 class="heading mt-8">For agents</h2>
        <p id="agents-markdown">
          Every page here is also Markdown: add .md to its address. Point an agent at
          <.a href={~p"/agents.md"}>{Web.Endpoint.host()}/agents.md</.a>
          and it can read the rest from there.
        </p>
      </div>
    </article>
    """
  end

  @doc "The page as Markdown, for /agents.md, with each page's Markdown address in full."
  def markdown do
    url = Web.Endpoint.url()

    uses =
      Enum.map_join(uses(), "\n", fn use ->
        """
        ## #{use.title}

        #{use.text}

        #{use.access}

        [#{use.link}](#{link(use, url)})
        """
      end)

    """
    # How agents work with SAR Duty

    #{lead()}

    #{uses}
    ## What stays in SAR Duty

    #{stays()}

    ## Who decides

    #{who()}
    """
  end

  # A page under /agents links its Markdown; the repository links as it is.
  defp link(%{path: path}, url), do: "#{url}#{path}.md"
  defp link(%{href: href}, _url), do: href

  defp lead do
    "An AI agent, such as Claude or ChatGPT, can help a team with SAR Duty, and so can the apps people build with one. Each thing they can do links to how."
  end

  defp stays do
    "The team's records: its members, activities, and equipment, and the rows of every report. Agents work from how a team is organized, or from what a card shows anyone holding it."
  end

  defp who do
    "SAR Duty decides which admins get AI writing, and it runs in SAR Duty: no agent connects to a team. A public check, such as an ID card's, shows only what anyone can see. Agents never change anything."
  end

  @repo "https://github.com/gshaw/sarduty"

  # What agents can do, each with its page under /agents or on GitHub. `access` says who decides.
  defp uses do
    [
      %{
        id: "agents-use-demo",
        title: "Show someone SAR Duty",
        text:
          "Someone new asks an agent what SAR Duty does, or whether it has a feature. The agent starts a demo, a made-up team of their own, tries the pages that answer the question, and hands them the link.",
        access: "Anyone can start a demo, with no key or login.",
        link: "How to show someone SAR Duty",
        path: ~p"/agents/demo"
      },
      %{
        id: "agents-use-reports",
        title: "Write reports",
        text:
          "A team admin describes a report in the report editor, such as members on Callout without First Aid, and AI writing writes its query. It tries the report on Coast Range SAR, a made-up team, and the team admin runs it on the team's records. Scripts and other agents can read the same report language.",
        access: "A team admin asks in SAR Duty. There is nothing to connect.",
        link: "How to write a report",
        path: ~p"/agents/reports"
      },
      %{
        id: "agents-use-forms",
        title: "Write forms",
        text:
          "A team or organization admin gives SAR Duty an agency's PDF, such as a task report. AI writing writes the form: what it fills in from an activity, and where each answer goes on the page. The admin tries it on an activity, marked SAMPLE, and saves it.",
        access:
          "An admin asks in SAR Duty, once SAR Duty turns on forms for their team or organization. There is nothing to connect.",
        link: "How forms are written",
        href: "#{@repo}/blob/main/docs/ai-writing.md#forms"
      },
      %{
        id: "agents-use-code",
        title: "Answer questions about SAR Duty",
        text:
          "SAR Duty's code and its docs are public. An agent pointed at the repository can read how a feature works or where a rule lives. It can answer general questions about SAR Duty.",
        access: "Public, with no key or login. The code holds no team's records.",
        link: "SAR Duty on GitHub",
        href: @repo
      },
      %{
        id: "agents-use-id-cards",
        title: "Check ID cards",
        text:
          "An app that signs members in scans their ID card and gets the verify site's answer: who it is, their team, and whether they are active.",
        access:
          "Public, with no key or login. It answers only what anyone holding the card can see.",
        link: "How to check an ID card",
        path: ~p"/agents/id-cards"
      }
    ]
  end
end

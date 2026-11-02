defmodule Web.ReportLanguageLive do
  use Web, :live_view_marketing_layout

  alias App.Report.Language

  # How to write a report (#803): public, for team admins and their agents. The same
  # text is at /agents/reports.md (Web.MarkdownController). It sits under /agents, so its
  # trail starts there (docs/navigation.md). The page is long, so a list of its sections
  # follows the intro, taken from its own headings. The Markdown has none: agents read it
  # whole.
  def mount(_params, _session, socket) do
    html = MDEx.to_html!(Language.markdown(), extension: [table: true, header_id_prefix: ""])
    [intro, rest] = String.split(html, "<h2", parts: 2)
    rest = "<h2" <> rest

    sections =
      for [_, id, title] <- Regex.scan(~r{<h2 id="([^"]+)">(.*?)</h2>}, rest),
          do: %{id: id, title: Phoenix.HTML.raw(title)}

    {:ok,
     assign(socket,
       page_title: "How to write a report",
       intro_html: Phoenix.HTML.raw(intro),
       rest_html: Phoenix.HTML.raw(rest),
       sections: sections
     )}
  end

  def render(assigns) do
    ~H"""
    <article id="report-language" class="container mx-auto px-2 pt-8">
      <.breadcrumbs>
        <:item label="Agents" path={~p"/agents"} />
        <:item label="How to write a report" />
      </.breadcrumbs>
      <div class="max-w-prose prose">{@intro_html}</div>
      <nav id="report-language-contents" aria-labelledby="report-language-contents-title" class="my-8">
        <h2 id="report-language-contents-title" class="subheading">On this page</h2>
        <ul class="list">
          <li :for={section <- @sections}><.a href={"#" <> section.id}>{section.title}</.a></li>
        </ul>
      </nav>
      <div class="max-w-prose prose">{@rest_html}</div>
    </article>
    """
  end
end

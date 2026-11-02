defmodule Web.ReportLanguageLive do
  use Web, :live_view_marketing_layout

  alias App.Report.Language

  # How to write a report (#803): public, for team admins and their agents. The same
  # text is at /agents/reports.md (Web.MarkdownController). It sits under /agents, so its
  # trail starts there (docs/navigation.md).
  def mount(_params, _session, socket) do
    html =
      Language.markdown()
      |> MDEx.to_html!(extension: [table: true, header_id_prefix: ""])
      |> Phoenix.HTML.raw()

    {:ok, assign(socket, page_title: "How to write a report", language_html: html)}
  end

  def render(assigns) do
    ~H"""
    <article id="report-language" class="container mx-auto px-2 pt-8">
      <.breadcrumbs>
        <:item label="Agents" path={~p"/agents"} />
        <:item label="How to write a report" />
      </.breadcrumbs>
      <div class="max-w-prose prose">{@language_html}</div>
    </article>
    """
  end
end

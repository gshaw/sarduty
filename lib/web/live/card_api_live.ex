defmodule Web.CardApiLive do
  use Web, :live_view_marketing_layout

  # How to check an ID card as JSON: public, under /agents, for the people and agents
  # building apps that scan cards. The text is Web.CardApiDoc's, also at
  # /agents/id-cards.md. Its trail starts at /agents (docs/navigation.md).
  def mount(_params, _session, socket) do
    html = MDEx.to_html!(Web.CardApiDoc.markdown(), extension: [header_id_prefix: ""])

    {:ok,
     assign(socket,
       page_title: "How to check an ID card",
       page_description:
         "Check a SAR Duty ID card as JSON: scan the code, get the member, their team, and whether they are active.",
       html: Phoenix.HTML.raw(html)
     )}
  end

  def render(assigns) do
    ~H"""
    <article id="card-api" class="container mx-auto px-2 pt-8">
      <.breadcrumbs>
        <:item label="Agents" path={~p"/agents"} />
        <:item label="How to check an ID card" />
      </.breadcrumbs>
      <div class="max-w-prose prose">{@html}</div>
    </article>
    """
  end
end

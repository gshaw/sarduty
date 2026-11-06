defmodule Web.DemoAgentsLive do
  use Web, :live_view_marketing_layout

  # How an agent shows someone SAR Duty on a demo (#857): public, under /agents. The text
  # is Web.DemoAgentsDoc's, also at /agents/demo.md.
  def mount(_params, _session, socket) do
    html = MDEx.to_html!(Web.DemoAgentsDoc.markdown(), extension: [header_id_prefix: ""])

    {:ok,
     assign(socket,
       page_title: "How to show someone SAR Duty",
       page_description:
         "Start a SAR Duty demo for someone, show them what it does, and hand them its link.",
       html: Phoenix.HTML.raw(html)
     )}
  end

  def render(assigns) do
    ~H"""
    <article id="demo-agents" class="container mx-auto px-2 pt-8">
      <.breadcrumbs>
        <:item label="Agents" path={~p"/agents"} />
        <:item label="How to show someone SAR Duty" />
      </.breadcrumbs>
      <div class="max-w-prose prose">{@html}</div>
    </article>
    """
  end
end

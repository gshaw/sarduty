defmodule Web.TermsLive do
  use Web, :live_view_marketing_layout

  # TERMS.md, kept short and general on purpose, like PRIVACY.md.
  @path Path.expand("../../../TERMS.md", __DIR__)
  @external_resource @path
  @html Web.Components.Markdown.markdown_file_html(@path)

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Terms",
       page_description:
         "The terms for search and rescue teams that use SAR Duty: what your team is responsible for, and what SAR Duty is not."
     )}
  end

  def render(assigns) do
    ~H"""
    <.markdown_page id="terms-page" html={html()} />
    """
  end

  defp html, do: @html
end

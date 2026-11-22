defmodule Web.ChangelogLive do
  use Web, :live_view_marketing_layout

  # The repo's CHANGELOG.md, read at compile time, so the page and GitHub show one text.
  @path Path.expand("../../../CHANGELOG.md", __DIR__)
  @external_resource @path
  @html Web.Components.Markdown.markdown_file_html(@path)

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Changelog",
       page_description: "What changed in SAR Duty for search and rescue teams, newest first."
     )}
  end

  def render(assigns) do
    ~H"""
    <.markdown_page id="changelog" html={html()} />
    """
  end

  defp html, do: @html
end

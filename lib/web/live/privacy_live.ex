defmodule Web.PrivacyLive do
  use Web, :live_view_marketing_layout

  # PRIVACY.md, kept short and general on purpose, so it holds while features change.
  # Update its date when the meaning changes.
  @path Path.expand("../../../PRIVACY.md", __DIR__)
  @external_resource @path
  @html Web.Components.Markdown.markdown_file_html(@path)

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Privacy",
       page_description:
         "What SAR Duty keeps about your team and its members, who sees it, and where it is stored."
     )}
  end

  def render(assigns) do
    ~H"""
    <.markdown_page id="privacy-page" html={html()} />
    """
  end

  defp html, do: @html
end

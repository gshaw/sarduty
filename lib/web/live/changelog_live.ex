defmodule Web.ChangelogLive do
  use Web, :live_view_marketing_layout

  # The repo's CHANGELOG.md, read at compile time, so the page and GitHub show one text.
  @changelog_path Path.expand("../../../CHANGELOG.md", __DIR__)
  @external_resource @changelog_path
  @changelog_html @changelog_path
                  |> File.read!()
                  |> MDEx.to_html!(extension: [header_id_prefix: ""])

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Changelog",
       page_description: "What changed in SAR Duty for search and rescue teams, newest first."
     )}
  end

  def render(assigns) do
    assigns = assign(assigns, changelog_html: Phoenix.HTML.raw(@changelog_html))

    ~H"""
    <article id="changelog" class="container mx-auto px-2 pt-8">
      <div class="max-w-prose prose">{@changelog_html}</div>
    </article>
    """
  end
end

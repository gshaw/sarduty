defmodule Web.Components.Markdown do
  use Web, :function_component

  attr :content, :string, required: true

  def markdown(assigns) do
    markdown_html = build_raw_html(assigns.content || "")
    assigns = assign(assigns, :markdown_html, markdown_html)

    ~H"""
    <div class="prose">
      {@markdown_html}
    </div>
    """
  end

  # D4H activity descriptions arrive as HTML that any D4H user can edit, so
  # raw HTML is kept but sanitized: no scripts, event handlers, or
  # `javascript:` links.
  defp build_raw_html(markdown_content) when is_binary(markdown_content) do
    markdown_content
    |> String.trim()
    |> MDEx.to_html!(
      extension: [autolink: true, strikethrough: true, table: true, tasklist: true],
      render: [hardbreaks: true, unsafe: true],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> Phoenix.HTML.raw()
  end

  defp build_raw_html(_), do: Phoenix.HTML.raw("<p>Content unavailable</p>")

  @doc "A repo Markdown file as HTML, for a page that reads it at compile time."
  def markdown_file_html(path),
    do: path |> File.read!() |> MDEx.to_html!(extension: [header_id_prefix: ""])

  attr :id, :string, required: true
  attr :html, :string, required: true, doc: "from markdown_file_html/1"

  # A public page that is one Markdown file in the repo, such as CHANGELOG.md, so the
  # page and GitHub show one text.
  def markdown_page(assigns) do
    ~H"""
    <article id={@id} class="page-frame pt-8">
      <div class="max-w-prose prose">{Phoenix.HTML.raw(@html)}</div>
    </article>
    """
  end
end

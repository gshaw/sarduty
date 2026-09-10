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
end

defmodule Web.Components.Markdown do
  use Web, :function_component

  attr :content, :string, required: true

  def markdown(assigns) do
    markdown_html = build_raw_html(assigns.content || "")
    assigns = assign(assigns, :markdown_html, markdown_html)

    ~H"""
    <div class="prose">
      <%= @markdown_html %>
    </div>
    """
  end

  defp build_raw_html(markdown_content) do
    markdown_content
    |> String.trim()
    |> Earmark.as_html!(code_class_prefix: "lang- language-")
    |> Phoenix.HTML.raw()
  end
end

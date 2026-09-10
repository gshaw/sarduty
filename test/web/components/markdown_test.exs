defmodule Web.Components.MarkdownTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Web.Components.Markdown

  defp render_markdown(content) do
    render_component(&Markdown.markdown/1, content: content)
  end

  test "renders Markdown" do
    html = render_markdown("Meet at the **hall**\nby 19:00")

    assert html =~ "<strong>hall</strong>"
    assert html =~ "<br"
  end

  test "keeps the formatting in D4H's HTML descriptions" do
    html = render_markdown("<p>Bring <em>radios</em></p><ul><li>Rope</li></ul>")

    assert html =~ "<em>radios</em>"
    assert html =~ "<li>Rope</li>"
  end

  test "strips scripts, event handlers, and javascript: links" do
    html =
      render_markdown("""
      <script>alert(1)</script>
      <img src="x" onerror="alert(2)">
      <a href="javascript:alert(3)">map</a>

      [directions](javascript:alert(4))
      """)

    refute html =~ "<script"
    refute html =~ "onerror"
    refute html =~ "javascript:"
  end
end

defmodule Web.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  # A narrow page's bar is the compact one at every width, and lines up with its column.
  test "the narrow layouts put the compact bar over one column of their width" do
    for {layout, width} <- [narrow: "max-w-md", narrow_tool: "max-w-3xl"] do
      document =
        Web.Layouts
        |> Function.capture(layout, 1)
        |> render_component(flash: %{}, inner_content: Phoenix.HTML.raw("<p id=\"page\"></p>"))
        |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query(".site-bar.site-bar-compact") |> Enum.count() == 1
      assert document |> LazyHTML.query(".site-bar-inner.#{width}") |> Enum.count() == 1
      assert document |> LazyHTML.query("main.#{width} #page") |> Enum.count() == 1
    end
  end

  test "the app layout's bar is compact only on small screens" do
    html = render_component(&Web.Layouts.app/1, flash: %{}, inner_content: Phoenix.HTML.raw(""))
    document = LazyHTML.from_fragment(html)

    assert document |> LazyHTML.query(".site-bar") |> Enum.count() == 1
    assert document |> LazyHTML.query(".site-bar-compact") |> Enum.count() == 0
  end
end

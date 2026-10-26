defmodule Web.Components.HeadingRowTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.HeadingRow

  test "the note and action go after the heading, and nothing when there are none" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.heading_row>
        <h2 class="heading">Members</h2>
        <:note>4 sent</:note>
        <:action><button>Add members</button></:action>
      </.heading_row>
      """)

    assert html =~ ~r{<h2 class="heading">Members</h2>\s*<div class="heading-row-end">}
    assert html =~ ~s(<span class="hint">4 sent</span>)

    bare = rendered_to_string(~H|<.heading_row>
  <h2>Members</h2>
</.heading_row>|)
    refute bare =~ "heading-row-end"
  end

  # One way to put an action beside a heading (#444): the component, never the class.
  test "only <.heading_row> makes a heading row" do
    by_hand =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          path != "lib/web/components/heading_row.ex",
          File.read!(path) =~ ~r/class="[^"]*\bheading-row\b/,
          do: path

    assert by_hand == [], "Use <.heading_row> in: #{inspect(by_hand)}"
  end
end

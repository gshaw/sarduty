defmodule Web.Components.CopyButtonTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.CopyButton

  test "copy_code_block/1 copies the block's text and names what it copies" do
    assigns = %{}

    document =
      ~H"""
      <.copy_code_block id="cmd" value="claude mcp add" label="Copy command" />
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query("pre#cmd.code-block") |> LazyHTML.text() == "claude mcp add"

    assert document
           |> LazyHTML.query(
             ~s(button#cmd-copy[value="claude mcp add"][aria-label="Copy command"])
           )
           |> Enum.count() == 1

    assert document |> LazyHTML.query("#cmd-copy-status") |> Enum.count() == 1
  end

  test "copy_button/1 shows nothing without a value" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.copy_button id="none" value={nil} label="Copy email" />
      """)

    assert String.trim(html) == ""
  end

  test "copy_button/1 keeps the text's last word on the button's line" do
    assigns = %{}

    document =
      ~H"""
      <.copy_button text="5756 142 St, Surrey" id="addr" value="5756 142 St" label="Copy address" />
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()

    assert document |> LazyHTML.text() |> String.trim() == "5756 142 St, Surrey"
    tail = LazyHTML.query(document, ".copy-tail")
    assert LazyHTML.text(tail) == "Surrey"
    assert tail |> LazyHTML.query("button#addr") |> Enum.count() == 1
  end

  test "copy_button/1 links the text with href, kept whole" do
    assigns = %{}

    document =
      ~H"""
      <.copy_button
        text="a@example.com"
        href="mailto:a@example.com"
        id="e"
        value="a@example.com"
        label="Copy email"
      />
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()

    assert document
           |> LazyHTML.query(~s(.copy-tail a[href="mailto:a@example.com"]))
           |> LazyHTML.text() ==
             "a@example.com"
  end
end

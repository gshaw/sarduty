defmodule Service.DescriptionTextTest do
  use ExUnit.Case, async: true

  alias Service.DescriptionText

  test "paragraphs and line breaks read as text, and go back as the same HTML" do
    html = "<p>Bring a headlamp &amp; map.</p>\n<p>Line one<br>Line two</p>"
    assert {:ok, text} = DescriptionText.to_text(html)
    assert text == "Bring a headlamp & map.\n\nLine one\nLine two"

    assert DescriptionText.to_html(text) ==
             "<p>Bring a headlamp &amp; map.</p><p>Line one<br>Line two</p>"
  end

  test "plain text stays as it is" do
    assert DescriptionText.to_text("Meet at the hall.") == {:ok, "Meet at the hall."}
  end

  test "links, lists, and styled paragraphs are formatting" do
    assert DescriptionText.to_text(~s(<p>See <a href="https://example.com">this</a></p>)) ==
             :formatted

    assert DescriptionText.to_text("<ul><li>Rope</li></ul>") == :formatted
    assert DescriptionText.to_text(~s(<p style="color: red">Late</p>)) == :formatted
  end

  test "empty paragraphs and blank text are no description" do
    assert DescriptionText.to_text("<p></p><p><br></p>") == {:ok, nil}
    assert DescriptionText.to_html("\r\n\r\n") == nil
    assert DescriptionText.to_html(nil) == nil
  end

  test "a browser's line endings and text that looks like HTML are escaped" do
    assert DescriptionText.to_html("a <b>\r\nc\r\n\r\nd") == "<p>a &lt;b&gt;<br>c</p><p>d</p>"
  end
end

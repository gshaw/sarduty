defmodule Service.DescriptionHTMLTest do
  use ExUnit.Case, async: true

  # cspell:ignore nbsp

  alias Service.DescriptionHTML

  test "a chore event's HTML stays as it is" do
    html =
      "<p><em>Made by SAR Duty.</em></p><p><strong>Sam Lee</strong>: 4 hours</p>" <>
        "<ul><li>Oct 24: Radio programming, 1 hour</li></ul><p>1 member, 1 chore.</p>"

    assert DescriptionHTML.clean(html) == html
    assert DescriptionHTML.editable?(html)
  end

  test "D4H's b, i, and newlines between tags become strong, em, and nothing" do
    assert DescriptionHTML.clean(
             "<p><b>Date:</b> <i>soon</i></p>\n<ol>\n<li>Call to order</li>\n</ol>"
           ) ==
             "<p><strong>Date:</strong> <em>soon</em></p><ol><li>Call to order</li></ol>"
  end

  test "Trix's blank lines start a paragraph, and one line break stays" do
    assert DescriptionHTML.clean("<div>One<br>Two<br><br>Three<br></div><div><br></div>") ==
             "<p>One<br>Two</p><p>Three</p>"
  end

  test "Trix's copy of a description cleans to the same HTML" do
    html =
      ~s(<p>Swiftwater refresher at <strong>Derby Reach</strong>.</p><p>Bring:</p>) <>
        ~s(<ul><li>Drysuit</li></ul><p>Map: <a href="https://example.com">Derby Reach</a></p>)

    # What Trix 2.1 puts in the input for it, line break in the link and all.
    trix =
      ~s(<div>Swiftwater refresher at <strong>Derby Reach</strong>.<br><br></div>) <>
        ~s(<div><br>Bring:<br><br></div><ul><li>Drysuit</li></ul>) <>
        ~s(<div><br>Map: <a href="https://example.com">Derby Reach<br></a><br></div>)

    assert DescriptionHTML.clean(trix) == html
  end

  test "tags around the same text nest link, bold, italic" do
    assert DescriptionHTML.clean(~s(<p><em><b><a href="https://example.com">Map</a></b></em></p>)) ==
             ~s(<p><a href="https://example.com"><strong><em>Map</em></strong></a></p>)
  end

  test "colours, fonts, and sizes go, and the text stays" do
    html =
      ~s(<p style="color: red"><span style="font-size: 20px">Late</span> <font face="Comic Sans">start</font></p>)

    assert DescriptionHTML.editable?(html)
    assert DescriptionHTML.clean(html) == "<p>Late start</p>"
  end

  test "links keep a web, mail, or phone address and lose anything else" do
    assert DescriptionHTML.clean(~s(<p><a href="https://example.com" target="_blank">Map</a></p>)) ==
             ~s(<p><a href="https://example.com">Map</a></p>)

    assert DescriptionHTML.clean(~s{<p><a href="javascript:alert(1)">Map</a></p>}) == "<p>Map</p>"
  end

  test "a nested list stays in its item, and a paragraph in an item is a line" do
    assert DescriptionHTML.clean("<ul><li><p>Rope</p><ul><li>50 m</li></ul></li><li></li></ul>") ==
             "<ul><li>Rope<ul><li>50 m</li></ul></li></ul>"
  end

  test "plain text becomes paragraphs and line breaks, escaped" do
    assert DescriptionHTML.clean("a &amp; b\r\nc\r\n\r\nd") == "<p>a &amp; b<br>c</p><p>d</p>"
    assert DescriptionHTML.clean("Meet at  the hall.") == "<p>Meet at the hall.</p>"
  end

  test "empty paragraphs and blank text are no description" do
    assert DescriptionHTML.clean("<p>&nbsp;</p><p><br></p>") == nil
    assert DescriptionHTML.clean("\r\n\r\n") == nil
    assert DescriptionHTML.clean(nil) == nil
  end

  test "cleaning twice gives the same HTML" do
    for html <- [
          "<p>a <span>b</span> c</p>",
          "Line one\nLine  two",
          "<div>x<br> <br>y</div>",
          "<p><b> </b>bold?</p>"
        ] do
      once = DescriptionHTML.clean(html)
      assert DescriptionHTML.clean(once) == once
    end
  end

  test "tables, pictures, headings, and rules are not editable" do
    for html <- [
          "<table><tr><td>1</td></tr></table>",
          ~s(<p><img src="x.png"></p>),
          "<h2>Plan</h2>",
          "<p>a</p><hr><p>b</p>"
        ] do
      refute DescriptionHTML.editable?(html), html
    end

    assert DescriptionHTML.editable?(nil)
    assert DescriptionHTML.editable?("Plain text")
  end
end

defmodule App.Document.MarkupTest do
  use ExUnit.Case, async: true

  # cspell:ignore Łukasz Nowak -- a name past WinAnsi (#917)

  alias App.Document.Markup

  @flow %{
    name: "letter",
    kind: :flow,
    across: false,
    top: 72,
    left: 72,
    right: 72,
    size: 12,
    leading: 14.4,
    value: []
  }
  @png <<0x89, "PNG", 13::32, 0::32, "IHDR", 400::32, 100::32>>

  defp output(places),
    do: %{title: "2025 SRVTC Coast Range", author: "Coast Range", places: places}

  test "writes every value as a string, so markup in it prints as written" do
    assert Markup.string(~s|*Bold* #x "q" \\ end\nnext|) ==
             ~s|"*Bold* #x \\"q\\" \\\\ end\\nnext"|

    {markup, files} = Markup.typst(output([%{@flow | value: [{:text, "Name: *Sam* #1"}]}]))

    assert markup =~ ~s|par("Name: *Sam* #1")|
    assert markup =~ ~s|#set document(title: "2025 SRVTC Coast Range", author: "Coast Range")|
    assert files == %{}
  end

  test "a flow's text is a line each, and a space a blank line" do
    value = [{:text, "PO Box 1\nHope BC"}, {:space, 2}, {:text, "End"}]
    {markup, _files} = Markup.typst(output([%{@flow | value: value}]))

    lines = Regex.scan(~r/^  par\((.*)\)$/m, markup, capture: :all_but_first)
    assert lines == [[~s|"PO Box 1"|], [~s|"Hope BC"|], ["hide[x]"], ["hide[x]"], [~s|"End"|]]
  end

  test "fits a picture in its box, keeping its shape" do
    value = [{:image, @png, %{width: 216, height: 54.0, pad: 6}}]
    {markup, files} = Markup.typst(output([%{@flow | value: value}]))

    # 400 by 100 fits 216 wide, 54 tall.
    assert markup =~ ~s|image("letter-0.png", width: 216.0pt, height: 54.0pt)|
    assert files == %{"letter-0.png" => @png}
  end

  test "puts a QR code level with a flow's last line, at the right" do
    verify = %{
      name: "verify",
      kind: :image,
      right: 72,
      width: 72,
      height: 72,
      level_with: "letter",
      value: {:qr, "https://verify.sarduty.com/letters/SRVTC-K7Q4M2XA"}
    }

    {markup, files} = Markup.typst(output([%{@flow | value: []}, verify]))

    assert markup =~ "dx: 468pt, dy: place_letter_top + measure(place_letter).height - 72pt"
    assert files["verify-0.svg"] =~ "<svg"
  end

  test "lays a flow across out from the right, and leaves out an empty one" do
    across = %{
      name: "letterhead",
      kind: :flow,
      across: true,
      top: 72,
      right: 72,
      height: 72,
      gap: 18.0,
      value: []
    }

    {markup, files} =
      Markup.typst(output([%{across | value: [{:image, @png, %{}}, {:image, @png, %{}}]}]))

    assert markup =~ "#place(top + right, dx: -72pt, dy: 72pt, stack(dir: ltr, spacing: 18.0pt"
    assert Map.keys(files) == ["letterhead-0.png", "letterhead-1.png"]

    assert {markup, %{}} = Markup.typst(output([%{across | value: []}]))
    refute markup =~ "stack"
  end

  test "draws the sample mark over the page" do
    {markup, files} = Markup.typst(output([]), sample_mark: @png)

    assert markup =~ ~s|image("sample-mark.png", width: 612pt)|
    assert files == %{"sample-mark.png" => @png}
  end

  test "the markup makes a PDF" do
    value = [{:text, "Łukasz Nowak"}, {:space, 1}, {:text, "End"}]
    {markup, _files} = Markup.typst(output([%{@flow | value: value}]))

    assert {:ok, "%PDF" <> _rest} = Service.Typst.compile(markup)
  end
end

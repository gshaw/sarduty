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

  # A form's page: letter paper, then legal (#950).
  @page """
  #set page(width: 612pt, height: 792pt)
  One
  #pagebreak()
  #set page(width: 612pt, height: 1008pt)
  Two
  """

  defp typst(places, opts \\ []) do
    %{title: "2025 SRVTC Coast Range", author: "Coast Range", places: places}
    |> Markup.typst(opts)
  end

  defp values(files), do: Jason.decode!(files["values.json"])

  test "values reach Typst as data, never as Typst code" do
    {markup, files} = typst([%{@flow | value: [{:text, ~s|Name: *Sam* #1 "q" \\ end|}]}])

    refute markup =~ "Sam"
    assert markup =~ ~s|#let v = json("values.json")|
    assert markup =~ ~s|par(v.at("letter").at(0))|
    assert markup =~ ~s|#set document(title: v.at("title"), author: v.at("author"))|

    assert values(files) == %{
             "title" => "2025 SRVTC Coast Range",
             "author" => "Coast Range",
             "letter" => [~s|Name: *Sam* #1 "q" \\ end|]
           }
  end

  test "a flow's text is a line each, and a space a blank line" do
    value = [{:text, "PO Box 1\nHope BC"}, {:space, 2}, {:text, "End"}]
    {markup, files} = typst([%{@flow | value: value}])

    lines = Regex.scan(~r/^  par\((.*)\)$/m, markup, capture: :all_but_first)

    assert lines == [
             [~s|v.at("letter").at(0)|],
             [~s|v.at("letter").at(1)|],
             ["hide[x]"],
             ["hide[x]"],
             [~s|v.at("letter").at(2)|]
           ]

    assert values(files)["letter"] == ["PO Box 1", "Hope BC", "End"]
  end

  test "fits a picture in its box, keeping its shape" do
    value = [{:image, @png, %{width: 216, height: 54.0, pad: 6}}]
    {markup, files} = typst([%{@flow | value: value}])

    # 400 by 100 fits 216 wide, 54 tall.
    assert markup =~ ~s|image("letter-0.png", width: 216.0pt, height: 54.0pt)|
    assert Map.delete(files, "values.json") == %{"letter-0.png" => @png}
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

    {markup, files} = typst([%{@flow | value: []}, verify])

    assert markup =~
             "place(top + right, dx: -72pt, dy: place_letter_top + measure(place_letter).height - 72pt"

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
      typst([%{across | value: [{:image, @png, %{}}, {:image, @png, %{}}]}])

    assert markup =~ "#place(top + right, dx: -72pt, dy: 72pt, stack(dir: ltr, spacing: 18.0pt"
    assert Map.keys(files) == ["letterhead-0.png", "letterhead-1.png", "values.json"]

    assert {markup, files} = typst([%{across | value: []}])
    assert Map.keys(files) == ["values.json"]
    refute markup =~ "stack"
  end

  test "draws the mark over the page" do
    {markup, files} = typst([], mark: @png)

    assert markup =~ ~s|image("mark.png", width: page-width)|
    assert files["mark.png"] == @png
  end

  test "the markup makes a PDF" do
    value = [{:text, "Łukasz Nowak"}, {:space, 1}, {:text, "End"}]
    {markup, files} = typst([%{@flow | value: value}])

    assert {:ok, "%PDF" <> _rest} = Service.Typst.compile(markup, files)
  end

  describe "a form's places" do
    defp text(options),
      do: Map.merge(%{name: "task", kind: :text, top: 112, left: 164, fit: false}, options)

    test "a text place wraps at its width, its lines a pitch apart" do
      {markup, files} =
        typst([
          text(%{width: 460, size: 10, pitch: 18, value: "Found on the ridge.\nWalked out."})
        ])

      assert markup =~ "block(width: 460pt"
      # 18pt baseline to baseline: 7.5pt to the first baseline, then 10.5pt to the next top.
      assert markup =~ "top-edge: 7.5pt, bottom-edge: \"baseline\""
      assert markup =~ "set par(leading: 10.5pt, spacing: 10.5pt)"
      assert markup =~ ~s|v.at("task").join(linebreak())|
      assert values(files)["task"] == ["Found on the ridge.", "Walked out."]
    end

    test "indent starts the first line after a printed label" do
      {markup, _files} = typst([text(%{width: 445, indent: 233, pitch: 13.6, value: "Found."})])
      assert markup =~ ~s|h(233pt) + v.at("task").join(linebreak())|
    end

    # EMCR's Details of Task has 8 lines (#950): a long text shrinks to them, its lines
    # still on the page's, rather than running into Equipment Used/Lost below.
    test "lines shrinks a long text until it fits that many of the page's lines" do
      place = text(%{width: 300, size: 10, pitch: 13.6, lines: 2})
      {markup, _files} = typst([Map.put(place, :value, "Found.")])

      # 7.5pt to the first baseline, 13.6pt to the second, and half a point to spare.
      assert markup =~ "measure(sized(s), width: room.width).height > 21.6pt"
      assert markup =~ "while s > 6pt"

      long = String.duplicate("Walked out at dusk with the subject. ", 12)

      for value <- ["Found.", long] do
        {markup, files} = typst([Map.put(place, :value, value)])
        assert {:ok, "%PDF" <> _rest} = Service.Typst.compile(markup, files)
      end
    end

    test "fit keeps one line and shrinks it to the place's width" do
      {markup, files} = typst([text(%{width: 132, size: 10, fit: true, value: "26-7310"})])

      assert markup =~ "block(width: 132pt, layout(room => {"
      assert markup =~ ~s|let body = v.at("task").join(" ")|
      assert markup =~ "text(size: 10pt * calc.min(1, room.width / wide * 0.999), body)"
      assert values(files)["task"] == ["26-7310"]
    end

    test "a place from the right edge, or as wide as its left and right leave" do
      {markup, _files} = typst([text(%{value: "x", left: 72, right: 72})])
      assert markup =~ "block(width: page-width - 72pt - 72pt"

      from_right = %{value: "x", width: 210, right: 72} |> text() |> Map.delete(:left)
      {markup, _files} = typst([from_right])

      assert markup =~ "#place(top + right, dx: -72pt, dy: 112pt, block(width: 210pt"
      assert markup =~ "set align(left)"
    end

    test "a tick draws an X across its box only when it holds" do
      tick = %{name: "err", kind: :tick, top: 110, left: 160, size: 9, value: true}
      {markup, _files} = typst([tick])

      assert markup =~ "#place(top + left, dx: 160pt, dy: 110pt, box(width: 9pt, height: 9pt"
      assert markup =~ "line(start: (15%, 15%), end: (85%, 85%), stroke: 0.9pt)"

      {markup, _files} = typst([%{tick | value: false}])
      refute markup =~ "line("
    end

    test "print on each page of the form's own page, at that page's size" do
      {:ok, page} = Service.Typst.compile(@page)
      first = text(%{value: "Overdue kayakers", width: 132, page: 1})
      second = %{name: "err", kind: :tick, top: 110, left: 160, size: 9, value: true, page: 2}

      {markup, files} = typst([first, second], page: {page, 2})

      assert markup =~ ~s|image("page.pdf", page: 1)|
      assert markup =~ ~s|image("page.pdf", page: 2)|
      assert files["page.pdf"] == page

      assert {:ok, pdf} = Service.Typst.compile(markup, files)
      assert Service.PDFPages.count(pdf) == {:ok, 2}

      assert Regex.scan(~r{/MediaBox\s*\[([^\]]*)\]}, pdf, capture: :all_but_first) ==
               [["0 0 612 792"], ["0 0 612 1008"]]
    end

    test "align right puts each line against the place's right edge" do
      {markup, _files} = typst([text(%{value: "$56.34", width: 44, fit: true, align: :right})])
      assert markup =~ "set align(right)"
    end

    # A form's rows past one page's (#950): each copy fills the same places with its own.
    test "print each copy of the form's page, each place with its own values" do
      {:ok, page} = Service.Typst.compile(@page)
      one = text(%{name: "page_number", value: "1 of 2", width: 132, copy: 1})
      two = text(%{name: "page_number", value: "2 of 2", width: 132, copy: 2})

      {markup, files} =
        Markup.typst(%{title: "Supplement", author: nil, copies: 2, places: [one, two]},
          page: {page, 2}
        )

      assert values(files)["page_number"] == ["1 of 2"]
      assert values(files)["page_number-copy2"] == ["2 of 2"]
      assert markup =~ ~s|v.at("page_number-copy2")|

      assert {:ok, pdf} = Service.Typst.compile(markup, files)
      assert Service.PDFPages.count(pdf) == {:ok, 4}
    end
  end

  describe "a layout" do
    @layout "#set page(width: 200pt, height: 100pt)\n#values.who\n"

    defp layout_output(fills) do
      %{
        title: "Expense reimbursement request CR-4113",
        author: "Coast Range SAR",
        places: [],
        layout: %{text: @layout, line: 40},
        fills: fills
      }
    end

    test "reads its values as data, and each picture is a file it names" do
      fills = %{
        "who" => ~s|*Sam* #1 "q"|,
        "far" => true,
        "signature" => {:image, @png},
        "address" => nil,
        "lines" => [%{"km" => "12"}]
      }

      {markup, files} = fills |> layout_output() |> Markup.typst()

      assert markup =~ ~s|#let values = json("values.json")\n|
      assert markup =~ ~s|#set document(title: values.at("title"), author: values.at("author"))|
      assert String.ends_with?(markup, @layout)
      refute markup =~ "Sam"

      assert values(files) == %{
               "title" => "Expense reimbursement request CR-4113",
               "author" => "Coast Range SAR",
               "who" => ~s|*Sam* #1 "q"|,
               "far" => true,
               "signature" => "signature.png",
               "address" => nil,
               "lines" => [%{"km" => "12"}]
             }

      assert files["signature.png"] == @png
    end

    test "the mark is each page's foreground" do
      {markup, files} = %{} |> layout_output() |> Markup.typst(mark: @png)

      assert markup =~
               ~s|#set page(foreground: place(top + left, image("mark.png", width: 100%)))|

      assert files["mark.png"] == @png
    end

    test "a mistake names the line of the form's text it's on" do
      output = layout_output(%{})
      {markup, _files} = Markup.typst(output)
      at = (markup |> String.split("\n") |> Enum.find_index(&(&1 == "#values.who"))) + 1

      reason =
        ~s|Typst stopped with status 1: main.typ:#{at}:9: error: dictionary does not contain key "who"|

      # The layout starts on line 40, so its second line is 41.
      assert Markup.layout_error(reason, markup, output) ==
               ~s|Line 41: dictionary does not contain key "who"|
    end
  end
end

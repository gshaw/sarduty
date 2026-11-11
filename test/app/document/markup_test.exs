defmodule App.Document.MarkupTest do
  use ExUnit.Case, async: true

  # cspell:ignore Łukasz Nowak luma -- a name past WinAnsi (#917), and Typst's grey

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
      value: {:qr, "https://verify.sarduty.com/K7Q4M-2XA9H-VB3TN"}
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

  describe "the verify code (#970)" do
    @link "https://verify.sarduty.com/K7Q4M-2XA9H-VB3TN"

    defp verify_typst(verify_code, verify, opts \\ []) do
      %{title: "Task report", author: "Coast Range", places: [], verify_code: verify_code}
      |> Markup.typst(Keyword.put(opts, :verify, verify))
    end

    test "prints bottom left by default: the link's QR code in capitals, and the link" do
      {markup, files} = verify_typst(%{at: :bottom_left, show: :both}, @link)

      assert markup =~ "#let verify-code = place(bottom + left, dx: 36pt, dy: -36pt,"
      assert markup =~ "[Verify this document]"
      assert markup =~ "#verify-code\n"
      assert values(files)["verify-link"] == "verify.sarduty.com/K7Q4M-2XA9H-VB3TN"

      qr = "HTTPS://VERIFY.SARDUTY.COM/K7Q4M-2XA9H-VB3TN" |> EQRCode.encode(:m) |> EQRCode.svg()
      assert files["verify-qr.svg"] == qr
    end

    test "on every page of a form's page" do
      {markup, _files} = verify_typst(%{at: :bottom_left, show: :both}, @link, page: {@page, 2})
      assert markup |> String.split("#verify-code\n") |> length() == 3
    end

    test "moves to a corner, the QR code in the corner" do
      {markup, _files} = verify_typst(%{at: :top_right, show: :both}, @link)

      assert markup =~ "place(top + right, dx: -36pt, dy: 36pt,"
      assert markup =~ ~r/Verify this document.*image\("verify-qr.svg"/s
    end

    test "prints the link alone, or the QR code alone" do
      {link, files} = verify_typst(%{at: :bottom_left, show: :link}, @link)
      refute link =~ "verify-qr.svg"
      refute files["verify-qr.svg"]

      {qr, _files} = verify_typst(%{at: :bottom_left, show: :qr}, @link)
      refute qr =~ "Verify this document"
    end

    test "prints nothing for none, or without a link" do
      {none, _files} = verify_typst(:none, @link)
      refute none =~ "verify-code"

      {unpublished, _files} = verify_typst(%{at: :bottom_left, show: :both}, nil)
      refute unpublished =~ "verify-code"
    end

    test "a draft prints a grey box in its place" do
      {markup, files} = verify_typst(%{at: :bottom_left, show: :both}, :draft)

      assert markup =~ "fill: luma(225)"
      assert markup =~ "The verify code prints here when this is published."
      refute files["verify-qr.svg"]
    end

    test "on a layout, it's each page's foreground with the mark" do
      output = %{
        title: "Expense request",
        author: "Coast Range",
        places: [],
        layout: %{text: "Hello\n", line: 10},
        fills: %{},
        verify_code: %{at: :bottom_left, show: :both}
      }

      {markup, _files} = Markup.typst(output, verify: @link, mark: @png)

      assert markup =~
               ~s|#set page(foreground: {verify-code; place(top + left, image("mark.png", width: 100%))})|
    end

    test "the markup makes a PDF" do
      {markup, files} = verify_typst(%{at: :bottom_right, show: :both}, @link)
      assert {:ok, "%PDF" <> _rest} = Service.Typst.compile(markup, files)

      {markup, files} = verify_typst(%{at: :top_left, show: :both}, :draft)
      assert {:ok, "%PDF" <> _rest} = Service.Typst.compile(markup, files)
    end
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

    # Too long at 8pt, a text that says more prints "See attached page" on its lines,
    # and the whole text on a page at the end (#993). Typst decides, so a short one adds
    # no page.
    test "more puts a text too long for its lines on an attached page" do
      place =
        text(%{
          name: "details",
          width: 300,
          size: 9,
          pitch: 12,
          lines: 2,
          more: "Details of Task",
          heading: "Coast Range SAR · Task report 26-06613 · Details of Task"
        })

      {markup, files} = typst([Map.put(place, :value, "Found.")])
      assert markup =~ "while s > 8pt"
      assert markup =~ "[See attached page]"
      assert markup =~ ~s|state("more-details", false).final()|
      assert values(files)["details-heading"] == place.heading
      refute markup =~ "Task report 26-06613"
      # Each attached page says what it belongs to and which of its pages it is.
      assert markup =~ ~s|header: attached-header(v.at("details-heading"), "more-details")|
      assert markup =~ ~s|", page " + str(n) + " of " + str(count)|

      # The verify code prints on it as on every page.
      {markup, _files} =
        Markup.typst(
          %{
            title: "Task report",
            author: "Coast Range",
            places: [Map.put(place, :value, "Found.")],
            verify_code: %{at: :bottom_left, show: :both}
          },
          verify: "https://v.test/K7Q4M"
        )

      assert markup =~ "foreground: {verify-code}"

      long = String.duplicate("Walked out at dusk with the subject. ", 12)
      longer = String.duplicate("Walked out at dusk with the subject.\n", 120)

      for {value, pages} <- [{"Found.", 1}, {long, 2}, {longer, 4}] do
        # DRAFT prints on the attached page too.
        mark = File.read!("priv/pdf/draft-mark.png")
        {markup, files} = typst([Map.put(place, :value, value)], mark: mark)
        assert markup =~ ~s|foreground: {place(top + left, image("mark.png", width: 100%))}|
        assert {:ok, pdf} = Service.Typst.compile(markup, files)
        assert Service.PDFPages.count(pdf) == {:ok, pages}
      end
    end

    test "attached? guesses from the text's length whether it goes on an attached page" do
      # 461pt at 8pt holds about 122 letters a line, so 10 lines about 1,220.
      place = text(%{width: 461, size: 9, pitch: 12, lines: 10, more: "Details of Task"})

      attached? = fn place, text -> place |> Map.put(:value, text) |> Markup.attached?() end

      refute attached?.(place, String.duplicate("x", 1200))
      assert attached?.(place, String.duplicate("x", 1300))
      # Each of its own lines starts a new one.
      assert attached?.(place, String.duplicate("x\n", 11))
      plain = Map.delete(place, :more)
      refute attached?.(plain, String.duplicate("x", 1300))
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
        "logo" => {:image, @png},
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
               "logo" => "logo.png",
               "address" => nil,
               "lines" => [%{"km" => "12"}]
             }

      assert files["logo.png"] == @png
    end

    test "the mark is each page's foreground" do
      {markup, files} = %{} |> layout_output() |> Markup.typst(mark: @png)

      assert markup =~
               ~s|#set page(foreground: {place(top + left, image("mark.png", width: 100%))})|

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

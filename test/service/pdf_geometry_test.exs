defmodule Service.PDFGeometryTest do
  # What a model writes a form's places from (#1083), checked against BCSARA's Task
  # report, whose places were measured by hand with pdfplumber.
  use ExUnit.Case, async: true

  alias Service.PDFGeometry

  setup_all do
    {:ok, pages} = "priv/forms/bcsara/task_report.pdf" |> File.read!() |> PDFGeometry.read()
    %{pages: pages}
  end

  test "reads each page's size and its lines of text, baseline and all", %{pages: pages} do
    assert [%{number: 1, width: 612.0, height: 792.0} = page] = pages
    task = Enum.find(page.lines, &(&1.text == "Task:"))
    assert %{x0: 64.9, x1: 84.4, baseline: 111.0, size: 7.8} = task
  end

  test "finds the rule after a label, where the place's numbers come from", %{pages: pages} do
    [page] = pages

    # task_number: top 106.4pt, left 88.8pt, width 110pt, size 9pt, on this rule.
    rule = Enum.find(page.rules, &(&1.y == 114.6 and &1.x0 < 100))
    assert rule == %{x0: 86.8, x1: 200.8, y: 114.6}
    assert_in_delta rule.x0 + 2, 88.8, 0.1
    assert_in_delta rule.x1 - rule.x0 - 4, 110.0, 0.1
    assert_in_delta rule.y - 1.5 - 0.75 * 9, 106.4, 0.1
  end

  test "finds the box Details of Task is written in", %{pages: pages} do
    [page] = pages

    # details: top 263pt, left 125.7pt, width 461pt.
    box = Enum.find(page.boxes, &(&1.top == 252.9))
    assert box == %{x0: 117.1, x1: 595.3, top: 252.9, bottom: 384.3}
    assert_in_delta box.x0 + 8.6, 125.7, 0.1
    assert_in_delta box.x1 - box.x0 - 17.2, 461.0, 0.1
  end

  test "a tick's box and a blank of underscores" do
    source = """
    #set page(width: 300pt, height: 200pt, margin: 0pt)
    #place(top + left, dx: 20pt, dy: 20pt)[Name: \\_\\_\\_\\_\\_\\_\\_\\_\\_\\_]
    #place(top + left, dx: 20pt, dy: 60pt, rect(width: 9pt, height: 9pt, stroke: 0.5pt))
    """

    {:ok, pdf} = Service.Typst.compile(source)
    {:ok, [page]} = PDFGeometry.read(pdf)

    assert [%{x0: x0, x1: x1}] = page.blanks
    assert x1 - x0 > 30
    assert page.boxes == [%{x0: 20.0, x1: 29.0, top: 60.0, bottom: 69.0}]
  end

  test "counts pages in order, since older MuPDF writes no page number (#1088)" do
    # Ubuntu 24.04's mupdf-tools 1.23 and Debian trixie's 1.25, as in CI and production.
    trace = """
    <page mediabox="0 0 300 200">
    <stroke_path linewidth="1" miterlimit="10" linejoin="0" linecap="0" colorspace="DeviceGray" color="0" transform="1 0 0 1 0 0">
    <moveto x="10" y="50"/>
    <lineto x="110" y="50"/>
    </stroke_path>
    </page>
    <page mediabox="0 0 300 200">
    <fill_path winding="nonzero" colorspace="DeviceGray" color="0" transform="1 0 0 1 0 0">
    <moveto x="20" y="60"/>
    <lineto x="80" y="60"/>
    <lineto x="80" y="90"/>
    <lineto x="20" y="90"/>
    </fill_path>
    </page>
    """

    assert PDFGeometry.read_paths(trace) == %{
             1 => %{rules: [%{x0: 10.0, x1: 110.0, y: 49.5}], boxes: []},
             2 => %{rules: [], boxes: [%{x0: 20.0, x1: 80.0, top: 60.0, bottom: 90.0}]}
           }
  end

  test "writes the pages out for a model, one line each, in points (#1088)" do
    page = %{
      number: 1,
      width: 612.0,
      height: 792.0,
      lines: [%{text: "Task: \"A\"", x0: 64.9, x1: 84.4, top: 103.2, baseline: 111.0, size: 7.8}],
      blanks: [],
      rules: [%{x0: 86.8, x1: 200.8, y: 114.6}],
      boxes: [%{x0: 117.1, x1: 595.3, top: 252.9, bottom: 384.3}]
    }

    assert PDFGeometry.describe([page, %{page | number: 2}]) == """
           Page 1: 612.0 wide and 792.0 high.

           Lines of text (x0 x1 top baseline size text):
           64.9 84.4 103.2 111.0 7.8 "Task: \\"A\\""

           Blanks, runs of underscores: none.

           Rules, drawn lines (x0 x1 y):
           86.8 200.8 114.6

           Boxes (x0 x1 top bottom):
           117.1 595.3 252.9 384.3

           Page 2: 612.0 wide and 792.0 high.

           Lines of text (x0 x1 top baseline size text):
           64.9 84.4 103.2 111.0 7.8 "Task: \\"A\\""

           Blanks, runs of underscores: none.

           Rules, drawn lines (x0 x1 y):
           86.8 200.8 114.6

           Boxes (x0 x1 top bottom):
           117.1 595.3 252.9 384.3
           """
  end

  test "writes out every line BCSARA's Task report prints", %{pages: pages} do
    text = PDFGeometry.describe(pages)
    assert text =~ ~s(64.9 84.4)
    assert text =~ ~s("Task:")
    assert text =~ "86.8 200.8 114.6"
  end

  test "a page that isn't a PDF is refused" do
    assert PDFGeometry.read("not a pdf") == {:error, "SAR Duty cannot read this PDF's page."}
  end
end

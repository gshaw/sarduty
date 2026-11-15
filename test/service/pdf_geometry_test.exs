defmodule Service.PDFGeometryTest do
  # What an agent writes a form's places from (#1083), checked against BCSARA's Task
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

  test "a page that isn't a PDF is refused" do
    assert PDFGeometry.read("not a pdf") == {:error, "SAR Duty cannot read this PDF's page."}
  end
end

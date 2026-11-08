defmodule Service.PDFPagesTest do
  use ExUnit.Case, async: true

  # cspell:ignore ObjStm FlateDecode endobj endstream -- PDF syntax names

  alias Service.PDFPages

  test "counts a Typst PDF's pages" do
    {:ok, pdf} = Service.Typst.compile("One\n#pagebreak()\nTwo\n#pagebreak()\nThree")
    assert PDFPages.count(pdf) == {:ok, 3}
  end

  # As Acrobat saves a form: the page tree in a compressed object stream, with a branch
  # under the root and a dictionary nested in the root.
  test "reads the page tree in a compressed object stream" do
    objects =
      "2 0 3 90 " <>
        "<< /Type /Pages /Resources << /Count 9 >> /Kids [3 0 R] /Count 4 >> " <>
        "<< /Type /Pages /Parent 2 0 R /Kids [4 0 R 5 0 R] /Count 2 >>"

    data = :zlib.compress(objects)

    pdf =
      "%PDF-1.5\n1 0 obj\n<< /Type /ObjStm /N 2 /First 10 /Filter /FlateDecode " <>
        "/Length #{byte_size(data)} >>\nstream\n#{data}\nendstream\nendobj\n%%EOF\n"

    assert PDFPages.count(pdf) == {:ok, 4}
  end

  # An update appended to a PDF writes its page tree again; a reader takes the last.
  test "takes the page tree an appended update wrote" do
    {:ok, pdf} = Service.Typst.compile("One\n#pagebreak()\nTwo\n#pagebreak()\nThree")
    update = "\n99 0 obj\n<</Type/Pages/Count 2/Kids[1 0 R 2 0 R]>>\nendobj\n%%EOF\n"

    assert PDFPages.count(pdf <> update) == {:ok, 2}
  end

  test "never guesses" do
    assert PDFPages.count("") == :error
    assert PDFPages.count("A page of text, not a PDF.") == :error
    assert PDFPages.count("%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n") == :error
  end
end

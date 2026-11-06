defmodule App.Operation.CheckTypstTest do
  use ExUnit.Case, async: true

  alias App.Operation.CheckTypst

  test "makes a test letter and locks it print-only" do
    assert {:ok, "Typst 0.15.1 works." <> _, locked} = CheckTypst.call()
    assert locked =~ "/Encrypt"
    assert {:ok, _key} = Service.PDFLock.file_key(locked)
  end

  test "the PDF needs all four of Arimo's fonts and the images" do
    {:ok, pdf} = Service.Typst.compile(~s|#set text(font: "Arimo")\nHi|)

    assert {:error, "The PDF has the fonts Arimo-Regular, not all four" <> _} =
             CheckTypst.check_pdf(pdf)
  end
end

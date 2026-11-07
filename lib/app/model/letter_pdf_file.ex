defmodule App.Model.LetterPDFFile do
  use App, :model

  alias App.Model.LetterPDF

  # A saved letter PDF's bytes (#918), apart from LetterPDF so lists never load them.
  schema "letter_pdf_files" do
    belongs_to :letter_pdf, LetterPDF
    field :bytes, :binary, redact: true
  end
end

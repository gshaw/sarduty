defmodule App.Model.SavedPDFFile do
  use App, :model

  alias App.Model.SavedPDF

  # A saved PDF's bytes (#918, #950), apart from SavedPDF so lists never load them.
  schema "saved_pdf_files" do
    belongs_to :saved_pdf, SavedPDF
    field :bytes, :binary, redact: true
  end
end

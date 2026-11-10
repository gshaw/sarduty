defmodule App.Model.PublishedPDFFile do
  use App, :model

  alias App.Model.PublishedPDF

  # A published PDF's bytes (#918, #970), apart from PublishedPDF so lists never load them.
  schema "published_pdf_files" do
    belongs_to :published_pdf, PublishedPDF
    field :bytes, :binary, redact: true
  end
end

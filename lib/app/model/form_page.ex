defmodule App.Model.FormPage do
  use App, :model

  alias App.Model.Form

  # A form's page PDF (#950), apart from Form so lists never load it.
  schema "form_pages" do
    belongs_to :form, Form
    field :bytes, :binary, redact: true
  end
end

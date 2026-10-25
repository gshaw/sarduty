defmodule Web.Components.FileDropTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.FileDrop

  alias Web.StyleGuideHTML.SampleData

  defp render_drop(upload, errors \\ []) do
    assigns = %{upload: upload, errors: errors}

    ~H"""
    <.file_drop
      id="cert"
      upload={@upload}
      label="Certificate"
      kinds="a photo or a PDF"
      errors={@errors}
    >
      Up to 10 MB.
    </.file_drop>
    """
    |> rendered_to_string()
    |> LazyHTML.from_fragment()
  end

  test "the box takes a drop and a paste for its upload, around the browser's own button" do
    upload = SampleData.sample_upload(:empty)
    document = render_drop(upload)

    assert [box] = document |> LazyHTML.query("#cert-drop.file-drop") |> Enum.to_list()
    assert LazyHTML.attribute(box, "phx-drop-target") == [upload.ref]
    assert LazyHTML.attribute(box, "phx-hook") == ["FileDrop"]
    assert LazyHTML.attribute(box, "data-upload") == ["certificate"]

    assert document
           |> LazyHTML.query("#cert-drop input[type=file]#" <> upload.ref)
           |> Enum.count() == 1

    assert document |> LazyHTML.query("label[for='#{upload.ref}']") |> LazyHTML.text() =~
             "Certificate"

    assert LazyHTML.text(document) =~ "Drop a photo or a PDF here, or paste one."
  end

  test "a file chosen shows with Remove, and a refused one says why" do
    document = render_drop(SampleData.sample_upload(:chosen))
    assert document |> LazyHTML.query("#cert-0") |> LazyHTML.text() =~ "first-aid.pdf"

    assert document
           |> LazyHTML.query("#cert-0 [phx-click=cancel-upload][phx-value-ref='0']")
           |> Enum.count() == 1

    document = render_drop(SampleData.sample_upload(:too_large), ["Select a photo or a PDF."])
    text = document |> LazyHTML.query("#cert.field-error") |> LazyHTML.text()
    assert text =~ "That file is too large. Use one under 10 MB."
    assert text =~ "Select a photo or a PDF."
    assert document |> LazyHTML.query("#cert-drop.is-invalid") |> Enum.count() == 1
  end
end

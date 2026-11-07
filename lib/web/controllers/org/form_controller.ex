defmodule Web.Org.FormController do
  use Web, :controller

  alias App.Model.Form
  alias App.Operation.TryForm

  # An organization's form as PDFs (#950): its blank page, and a try on Coast Range SAR.
  # Found through the URL's organization, so another's is a 404.

  def page(conn, %{"id" => id}) do
    form = form!(conn, id)

    case Form.page_bytes(form) do
      nil -> raise Web.Status.NotFound
      bytes -> send_pdf(conn, bytes, "#{form.name} page.pdf")
    end
  end

  def try(conn, %{"id" => id} = params) do
    form = form!(conn, id)

    case TryForm.call(form, params["activity"]) do
      {:ok, attachment} ->
        send_pdf(conn, attachment.content, "Sample #{attachment.filename}")

      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/orgs/#{conn.assigns.current_organization}/forms/#{form}")
    end
  end

  defp form!(conn, id),
    do: Form.get(conn.assigns.current_organization, id) || raise(Web.Status.NotFound)

  defp send_pdf(conn, bytes, filename) do
    send_download(conn, {:binary, bytes},
      filename: Service.StringHelpers.to_filename(filename),
      content_type: "application/pdf",
      disposition: :inline
    )
  end
end

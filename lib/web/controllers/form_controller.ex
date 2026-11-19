defmodule Web.FormController do
  use Web, :controller

  alias App.Model.Form
  alias App.Operation.TryForm
  alias Web.FormOwner

  # A form as PDFs (#950): its blank page, and a try, for an organization's form or a
  # team's own (#1083). Found through the URL's organization or team, so another's is a
  # 404, and a team's while team forms are off. A team tries its organization's forms on
  # its own activities too.

  def page(conn, %{"id" => id}) do
    {_owner, form} = form!(conn, id)

    case Form.page_bytes(form) do
      nil -> raise Web.Status.NotFound
      bytes -> send_pdf(conn, bytes, "#{form.name} page.pdf")
    end
  end

  def try(conn, %{"id" => id} = params) do
    {owner, form} = form!(conn, id)

    case TryForm.call(form, owner, params["activity"]) do
      {:ok, attachment} ->
        send_pdf(conn, attachment.content, "Sample #{attachment.filename}")

      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: FormOwner.form_path(owner, form))
    end
  end

  defp form!(conn, id) do
    owner = FormOwner.viewer(conn.assigns)
    {form, _own?} = FormOwner.form!(owner, id)
    {owner, form}
  end

  defp send_pdf(conn, bytes, filename) do
    send_download(conn, {:binary, bytes},
      filename: Service.StringHelpers.to_filename(filename),
      content_type: "application/pdf",
      disposition: :inline
    )
  end
end

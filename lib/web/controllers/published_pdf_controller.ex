defmodule Web.PublishedPDFController do
  use Web, :controller

  alias App.Model.PublishedPDF

  # A published PDF as it was saved (#970), for the team's admins: a letter's or a form's,
  # current or replaced or withdrawn, which its page marks as such. Inline, so it opens
  # in the browser. Another team's is a 404.
  def show(conn, %{"id" => id}) do
    attachment = conn |> find!(id) |> PublishedPDF.attachment()

    send_download(conn, {:binary, attachment.content},
      filename: attachment.filename,
      content_type: attachment.content_type,
      disposition: :inline
    )
  end

  # Page 1 as a picture, for the preview on its letter's or form's page, drawn from the
  # saved PDF each time it's asked for. A published PDF never changes, so the browser
  # keeps it.
  def preview(conn, %{"id" => id}) do
    attachment = conn |> find!(id) |> PublishedPDF.attachment()

    case Service.PDFImages.first_page(attachment.content) do
      {:ok, png} ->
        conn
        |> put_resp_header("cache-control", "private, max-age=31536000, immutable")
        |> put_resp_content_type("image/png", nil)
        |> send_resp(200, png)

      {:error, _reason} ->
        send_resp(conn, :not_found, "")
    end
  end

  defp find!(conn, id),
    do: PublishedPDF.get(conn.assigns.current_team, id) || raise(Web.Status.NotFound)
end

defmodule Web.PublishedPDFController do
  use Web, :controller

  alias App.Model.PublishedPDF

  # A published PDF as it was saved (#970), for the team's admins: a form's on its page,
  # a current one or one replaced or withdrawn, which the page marks as such. Inline, so
  # it opens in the browser. Another team's is a 404.
  def show(conn, %{"id" => id}) do
    pdf = PublishedPDF.get(conn.assigns.current_team, id) || raise(Web.Status.NotFound)
    attachment = PublishedPDF.attachment(pdf)

    send_download(conn, {:binary, attachment.content},
      filename: attachment.filename,
      content_type: attachment.content_type,
      disposition: :inline
    )
  end
end

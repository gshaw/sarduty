defmodule Web.TaxCreditLetterController do
  use Web, :controller

  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter

  # A letter's PDF as it was published (#918, #970), current or not.
  def show(conn, %{"id" => id}) do
    attachment =
      conn.assigns.current_team |> TaxCreditLetter.find!(id) |> PublishedPDF.attachment()

    conn
    |> put_resp_content_type(attachment.content_type)
    |> send_resp(200, attachment.content)
  end
end

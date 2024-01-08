defmodule Web.TaxCreditLetterController do
  use Web, :controller

  alias App.Model.TaxCreditLetter
  alias Service.PDFLetter

  def show(conn, %{"id" => tax_credit_letter_id}) do
    tax_credit_letter = TaxCreditLetter.get!(tax_credit_letter_id)

    pdf_contents =
      PDFLetter.build(%{
        title: "SAR Volunteer Tax Credit #{tax_credit_letter.year}",
        author: "South Fraser SAR",
        creator: "SARDuty.com",
        logo_path: "assets/img/logo-sfsar.png",
        content: tax_credit_letter.letter_content
      })

    conn
    |> put_resp_content_type("application/pdf")
    |> send_resp(200, pdf_contents)
  end
end

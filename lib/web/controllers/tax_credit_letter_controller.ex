defmodule Web.TaxCreditLetterController do
  use Web, :controller

  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildTaxCreditLetterAttachment

  def show(conn, %{"id" => tax_credit_letter_id}) do
    tax_credit_letter = TaxCreditLetter.find(conn.assigns.current_team, tax_credit_letter_id)
    attachment = BuildTaxCreditLetterAttachment.call(tax_credit_letter)

    conn
    |> put_resp_content_type(attachment.content_type)
    |> send_resp(200, attachment.content)
  end
end

defmodule Web.TaxCreditLetterController do
  use Web, :controller

  alias App.Model.Member
  alias App.Operation.PrintTaxCreditLetter

  # Page 1 of a member's letter for a year as it prints today, marked DRAFT (#970): the
  # letter page's preview before there's a letter. Printed each time and never kept, so
  # the browser keeps none either. A member of another team is a 404.
  def draft(conn, %{"year" => year, "id" => member_id}) do
    team = conn.assigns.current_team
    year = Web.TaxCreditLetterLive.parse_year(year) || raise(Web.Status.NotFound)
    member = Member.find!(team, member_id)
    read = PrintTaxCreditLetter.read(team, member.id, year, DateTime.utc_now())

    with {:ok, pdf} <- PrintTaxCreditLetter.draft(team, read),
         {:ok, png} <- Service.PDFImages.first_page(pdf) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_content_type("image/png", nil)
      |> send_resp(200, png)
    else
      {:error, _reason} -> send_resp(conn, :not_found, "")
    end
  end
end

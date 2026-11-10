defmodule App.Operation.RenewLetterCodes do
  @moduledoc """
  Gives each tax credit letter from before #970 a 15-character ID in place of its old
  reference number, and prints its saved PDF again with the new verify code, so no saved
  PDF carries a code that no longer verifies. Each letter keeps its one PDF row: its ID,
  bytes, and checksum change in place, never Replaced. It prints from the letter's own
  hours and date, as the letter said. Runs once after #970 deploys, through
  App.Worker.RenewLetterCodesWorker, and goes with part 3 of #970.
  """

  import Ecto.Query

  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.PrintTaxCreditLetter
  alias App.Repo

  require Logger

  @doc """
  Renews up to `limit` letters with an old code, those after id `after_id`: the last id
  it tried, or nil when none are left. A letter that doesn't print is logged and passed
  over, so the next batch moves on.
  """
  def batch(after_id, limit) do
    pdfs =
      old_codes()
      |> where([p], p.id > ^after_id)
      |> order_by([p], asc: p.id)
      |> limit(^limit)
      |> Repo.all()

    Enum.each(pdfs, &renew/1)
    pdfs |> List.last() |> then(&(&1 && &1.id))
  end

  @doc "How many letters still have an old code."
  def remaining, do: Repo.aggregate(old_codes(), :count)

  defp old_codes do
    where(
      PublishedPDF,
      [p],
      not is_nil(p.tax_credit_letter_id) and fragment("length(?)", p.code) != 15
    )
  end

  @doc "Gives one letter's PDF a new ID and prints it again: `{:ok, pdf}` or `{:error, reason}`."
  def renew(%PublishedPDF{} = pdf) do
    letter = TaxCreditLetter |> Repo.get!(pdf.tax_credit_letter_id) |> Repo.preload(member: :team)
    code = PublishedPDF.generate_code()

    case PrintTaxCreditLetter.call(letter, code) do
      {:ok, printed} ->
        {:ok, PublishedPDF.reprint!(pdf, printed)}

      {:error, reason} ->
        Logger.error("Letter PDF #{pdf.id} didn't print with a new code: #{reason}")
        {:error, reason}
    end
  end
end

defmodule App.Worker.SaveLetterPDFsWorker do
  @moduledoc """
  Saves a PDF for each tax credit letter made before letters kept theirs (#918), drawn
  by today's code with the team's logos now, as a download got it. Oban's cron starts
  it at every boot. It walks the letters in id order, 25 a job, and queues the next 25
  with where it got to, so a letter that can't be drawn (#917) is passed over rather
  than tried again forever. At the end it records a `letter_pdfs_saved` event with the
  count and the letters left without one; a walk that saved nothing and passed nothing
  over records none.

  Safe to run twice: each job reads only letters still without a PDF, so a walk that a
  deploy cut short, or two walks at once, save each letter once. Until a letter's turn
  comes, its download or email draws and saves it (App.Operation.LoadTaxCreditLetterPDF).
  Step 4 of #918 removes this worker, once every letter has a PDF.
  """

  use Oban.Worker,
    queue: :bulk,
    max_attempts: 3,
    unique: [states: :incomplete, period: :infinity]

  alias App.Model.Event
  alias App.Model.LetterPDF
  alias App.Operation.SaveTaxCreditLetterPDF

  require Logger

  @batch 25

  @doc "Queues the next batch: letters past `after_id`, with the counts so far."
  def enqueue(after_id, saved, failed_ids) do
    %{after_id: after_id, saved: saved, failed_ids: failed_ids}
    |> new()
    |> Oban.insert!()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    after_id = args["after_id"] || 0
    saved = args["saved"] || 0
    failed_ids = args["failed_ids"] || []

    case LetterPDF.missing(after_id, @batch) do
      [] ->
        finish(saved, failed_ids)

      letters ->
        failed = Enum.reject(letters, &save/1)

        enqueue(
          List.last(letters).id,
          saved + length(letters) - length(failed),
          failed_ids ++ Enum.map(failed, & &1.id)
        )

        :ok
    end
  end

  defp save(letter) do
    case SaveTaxCreditLetterPDF.call(letter) do
      {:ok, _attachment} ->
        true

      {:error, reason} ->
        Logger.warning("Tax credit letter #{letter.id} has no PDF: #{reason}")
        false
    end
  end

  defp finish(0, []), do: :ok

  defp finish(saved, failed_ids) do
    Event.record!(:letter_pdfs_saved, data: %{saved: saved, failed_letter_ids: failed_ids})
    Logger.info("Saved #{saved} letter PDFs; #{length(failed_ids)} could not be drawn")
    :ok
  end
end

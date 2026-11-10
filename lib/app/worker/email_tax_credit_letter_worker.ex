defmodule App.Worker.EmailTaxCreditLetterWorker do
  @moduledoc """
  Emails one tax credit letter made by sending every letter at once
  (App.Operation.CreateTaxCreditLetters.email/2). A refusal is tried again over about
  two hours; the last refusal marks the letter's email failed, which its row shows.
  """

  use Oban.Worker, queue: :bulk, max_attempts: 5

  alias App.Model.PublishedPDF
  alias App.Operation.CreateTaxCreditLetters

  @doc "Queues the letter's email. Call it in the transaction that publishes the letter."
  def enqueue(%PublishedPDF{id: id}), do: %{published_pdf_id: id} |> new() |> Oban.insert!()

  # After 10, 20, 30, then 40 minutes.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 10 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"published_pdf_id" => id}} = job),
    do: CreateTaxCreditLetters.email(id, job.attempt >= job.max_attempts)
end

defmodule App.Worker.EmailSignRequestWorker do
  @moduledoc """
  The two emails a request to sign sends (#993, App.Operation.AskToSign): the task
  leader's, with a link to the sign page, when a team admin asks; and the asker's, with
  the PDF attached, when the task leader signs. Queued with the request or the PDF;
  nobody waits for it, and a refusal is tried again over a few hours. A rare second
  email is fine.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias App.Accounts.User
  alias App.Mailer.SignedFormMailer
  alias App.Mailer.SignRequestMailer
  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.SignRequest
  alias App.Operation.PublishDocument
  alias App.Repo

  @doc "Queues the task leader's email. Call it in the transaction that asks."
  def enqueue_ask(%SignRequest{id: id}),
    do: %{sign_request_id: id} |> new() |> Oban.insert!()

  @doc "Queues the asker's email with the PDF. Call it in the transaction that publishes."
  def enqueue_signed(%SignRequest{id: id}, %PublishedPDF{id: pdf_id}),
    do: %{sign_request_id: id, published_pdf_id: pdf_id} |> new() |> Oban.insert!()

  # After 30 minutes, an hour, then 90 minutes and 2 hours.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 30 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sign_request_id" => id, "published_pdf_id" => pdf_id}}) do
    request = SignRequest |> Repo.get(id) |> Repo.preload([:asked_by, :member])
    pdf = PublishedPDF |> Repo.get(pdf_id) |> Repo.preload([:activity, :team])

    case {request, pdf} do
      {%SignRequest{asked_by: %User{}}, %PublishedPDF{}} ->
        url = if asker_admin?(request, pdf), do: SignedFormMailer.form_url(pdf)
        sent(SignRequestMailer.deliver_signed(request, pdf, PublishedPDF.attachment(pdf), url))

      _gone ->
        {:cancel, "no request, asker, or PDF"}
    end
  end

  def perform(%Oban.Job{args: %{"sign_request_id" => id}}) do
    request = SignRequest |> Repo.get(id) |> Repo.preload([:team, :activity, :member, :asked_by])

    case request do
      %SignRequest{ended_at: nil, member: %Member{email: email}} when email not in [nil, ""] ->
        sent(SignRequestMailer.deliver_ask(request, DateTime.utc_now()))

      _ended_or_no_email ->
        {:cancel, "the request ended, or the member has no email"}
    end
  end

  defp asker_admin?(request, pdf),
    do: PublishDocument.team_admin?(pdf.team, request.asked_by, DateTime.utc_now())

  defp sent({:ok, _metadata}), do: :ok
  defp sent({:error, reason}), do: {:error, reason}
end

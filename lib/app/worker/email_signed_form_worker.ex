defmodule App.Worker.EmailSignedFormWorker do
  @moduledoc """
  Tells a task leader, at their email, that a team admin signed a form for them (#993),
  with the PDF attached. Queued with the PDF; nobody waits for it, and a refusal is tried
  again over a few hours. A rare second email is fine.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias App.Mailer.SignedFormMailer
  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Repo

  @doc "Queues the email. Call it in the transaction that publishes the PDF."
  def enqueue(%PublishedPDF{id: id}, %Member{id: member_id}),
    do: %{published_pdf_id: id, member_id: member_id} |> new() |> Oban.insert!()

  # After 30 minutes, an hour, then 90 minutes and 2 hours.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 30 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"published_pdf_id" => pdf_id, "member_id" => member_id}}) do
    pdf = PublishedPDF |> Repo.get(pdf_id) |> Repo.preload([:activity, :team])
    member = Repo.get(Member, member_id)

    case {pdf, member} do
      {%PublishedPDF{}, %Member{email: email}} when email not in [nil, ""] ->
        with {:ok, _metadata} <-
               SignedFormMailer.deliver(member, pdf, PublishedPDF.attachment(pdf)),
             do: :ok

      _gone_or_no_email ->
        {:cancel, "no PDF, or no member with an email"}
    end
  end
end

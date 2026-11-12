defmodule App.Mailer.SignedFormMailer do
  @moduledoc """
  The email a task leader gets when a team admin signs a form for them (#993): who
  signed what, for which activity, and when, with the PDF attached. A task leader who's
  a team admin also gets a link to the form's page, for its history; anyone else gets
  only the PDF, since only team admins open that page.
  """
  import Swoosh.Email

  alias App.Mailer

  require Logger

  @doc """
  Emails `member`, the task leader, the published PDF `pdf` someone signed for them,
  with its team and activity loaded, and its `attachment`. `url` is the form's page, or
  nil when they can't open it.
  """
  def deliver(member, pdf, attachment, url) do
    email =
      new()
      |> Mailer.to_member(member)
      |> from({"SAR Duty", "noreply@sarduty.com"})
      |> subject(subject(pdf))
      |> text_body(body(pdf, url))
      |> attachment(
        Swoosh.Attachment.new(
          {:data, attachment.content},
          filename: attachment.filename,
          content_type: attachment.content_type
        )
      )
      |> Mailer.for_team(pdf.team)

    case Mailer.deliver(email) do
      {:ok, metadata} ->
        Logger.notice("delivered email metadata: #{inspect(metadata)}")
        {:ok, metadata}

      {:error, reason} ->
        Logger.error("email error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Pure. \"Alex Chen signed Task report 26-06613 for you\"."
  def subject(pdf), do: "#{pdf.signed_by} signed #{pdf.title} for you"

  @doc """
  Pure. "Alex Chen signed Task report 26-06613, Missing hiker, for you on Nov 11, 2026.
  It's attached.", then "Open it in SAR Duty:" and `url` when there is one.
  """
  def body(pdf, url) do
    day = Service.Format.date_short(pdf.inserted_at, pdf.team.timezone)
    what = Enum.reject([pdf.title, pdf.activity && pdf.activity.title], &(&1 in [nil, ""]))
    signed = "#{pdf.signed_by} signed #{Enum.join(what, ", ")}, for you on #{day}. It's attached."
    with_link(signed, url)
  end

  @doc "Pure. `text`, then the form's page when there is one, as a plain-text email."
  def with_link(text, nil), do: text <> "\n"
  def with_link(text, url), do: "#{text}\n\nOpen it in SAR Duty:\n#{url}\n"

  @doc "The form's page on its activity, which only team admins open."
  def form_url(pdf),
    do:
      Web.Endpoint.url() <>
        "/teams/#{pdf.team.subdomain}/activities/#{pdf.activity_id}/forms/#{pdf.form_id}"
end

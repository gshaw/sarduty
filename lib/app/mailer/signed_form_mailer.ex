defmodule App.Mailer.SignedFormMailer do
  @moduledoc """
  The email a task leader gets when a team admin signs a form for them (#993): who
  signed what, for which activity, and when, with the PDF attached.
  """
  import Swoosh.Email

  alias App.Mailer

  require Logger

  @doc """
  Emails `member`, the task leader, the published PDF `pdf` someone signed for them,
  with its team and activity loaded, and its `attachment`.
  """
  def deliver(member, pdf, attachment) do
    email =
      new()
      |> to(member.email)
      |> from({"SAR Duty", "noreply@sarduty.com"})
      |> subject(subject(pdf))
      |> text_body(body(pdf))
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
  It's attached."
  """
  def body(pdf) do
    day = Service.Format.date_short(pdf.inserted_at, pdf.team.timezone)
    what = Enum.reject([pdf.title, pdf.activity && pdf.activity.title], &(&1 in [nil, ""]))

    "#{pdf.signed_by} signed #{Enum.join(what, ", ")}, for you on #{day}. It's attached.\n"
  end
end

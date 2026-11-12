defmodule App.Mailer.SignRequestMailer do
  @moduledoc """
  The emails a request to sign sends (#993): the task leader's, asking them to sign
  with a link to the sign page, and the asker's, with the PDF the task leader signed.
  """
  import Swoosh.Email

  alias App.Mailer
  alias App.Mailer.SignedFormMailer
  alias App.Model.Member

  # A text link styled as a button, inline since Gmail strips classes, as the ID card's
  # email has it.
  @button "display:inline-block;padding:10px 16px;border-radius:4px;font-weight:700;" <>
            "text-decoration:none;background:#1d4f91;color:#ffffff;"

  @doc """
  Emails the task leader `request` asks to sign it, with a link to the sign page.
  Expects the request with its team, activity, member, and asked_by.
  """
  def deliver_ask(request, now) do
    %{member: member, team: team} = request
    paragraphs = ask_paragraphs(request, asker(request, now), sign_url(request))

    new()
    |> Mailer.to_member(member)
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject(ask_subject(request))
    |> text_body(Enum.map_join(paragraphs, "\n\n", &text/1) <> "\n")
    |> html_body(Enum.map_join(paragraphs, "\n", &html/1) <> "\n")
    |> Mailer.for_team(team)
    |> Mailer.deliver()
  end

  @doc "Pure. \"Sign Task report 26-06613\"."
  def ask_subject(request), do: "Sign #{request.title}"

  @doc """
  Pure. The task leader's email, as plain paragraphs and `{:button, label, url}`, so its
  text and HTML can't drift apart.
  """
  def ask_paragraphs(request, asker, url) do
    [
      "Hi #{request.member.name},",
      "#{asker} asked you to sign #{request.title} for #{request.activity.title}. Check it, then sign. Signing publishes it for #{request.team.name}.",
      {:button, "Sign #{request.title}", url},
      "#{request.team.name}, through SAR Duty"
    ]
  end

  # Who asked, by their member name on the team.
  defp asker(%{asked_by: nil}, _now), do: "A team admin"
  defp asker(request, now), do: Member.name_for_user(request.team, request.asked_by, now)

  defp sign_url(request),
    do:
      Web.Endpoint.url() <>
        "/teams/#{request.team.subdomain}/activities/#{request.activity_id}/forms/#{request.form_id}/sign"

  @doc """
  Emails the team admin who asked the PDF the task leader signed. Expects `request`
  with its member and asked_by, and `pdf` with its team and activity. `url` is the
  form's page, or nil when they're no longer a team admin.
  """
  def deliver_signed(request, pdf, attachment, url) do
    new()
    |> to(request.asked_by.email)
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject(signed_subject(pdf))
    |> text_body(signed_body(pdf, url))
    |> attachment(
      Swoosh.Attachment.new(
        {:data, attachment.content},
        filename: attachment.filename,
        content_type: attachment.content_type
      )
    )
    |> Mailer.for_team(pdf.team)
    |> Mailer.deliver()
  end

  @doc "Pure. \"Cameron Ruiz signed Task report 26-06613\"."
  def signed_subject(pdf), do: "#{pdf.signed_by} signed #{pdf.title}"

  @doc """
  Pure. "Cameron Ruiz signed Task report 26-06613, Missing hiker, on Nov 11, 2026.
  It's published, and attached.", then a link to the form's page when there's `url`.
  """
  def signed_body(pdf, url) do
    day = Service.Format.date_short(pdf.inserted_at, pdf.team.timezone)
    what = Enum.reject([pdf.title, pdf.activity && pdf.activity.title], &(&1 in [nil, ""]))

    "#{pdf.signed_by} signed #{Enum.join(what, ", ")}, on #{day}. It's published, and attached."
    |> SignedFormMailer.with_link(url)
  end

  defp text({:button, label, url}), do: "#{label}:\n#{url}"
  defp text(paragraph), do: paragraph

  defp html({:button, label, url}),
    do: ~s(<p><a href="#{escape(url)}" style="#{@button}">#{escape(label)}</a></p>)

  defp html(paragraph), do: "<p>#{escape(paragraph)}</p>"

  defp escape(string), do: string |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end

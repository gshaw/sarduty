defmodule App.Mailer.PhotoAskMailer do
  @moduledoc """
  The email that asks a member for a photo (#1030): from SAR Duty, with replies going to
  the team admin who asked, under the team's name. Its button opens Add a photo for the
  member with no login (Web.PhotoAskLinks).
  """
  import Swoosh.Email

  alias App.Mailer

  # A text link styled as a button, inline since Gmail strips classes, as the ID card's
  # email has it.
  @button "display:inline-block;padding:10px 16px;border-radius:4px;font-weight:700;" <>
            "text-decoration:none;background:#1d4f91;color:#ffffff;"

  @doc """
  Emails `member` the ask. `asker` is `%{name:, email:}`, the team admin who asked, or
  nil when their login is gone; `message` their own words, or nil; `url` the link; and
  `clean_up?` whether Clean up is available (#1031), so any background works.
  """
  def deliver(member, team, asker, message, url, clean_up?) do
    member
    |> build(team, asker, message, url, clean_up?)
    |> Mailer.for_team(team)
    |> Mailer.deliver()
  end

  defp build(member, team, asker, message, url, clean_up?) do
    paragraphs = paragraphs(member, team, asker, message, url, clean_up?)

    new()
    |> to({member.name, member.email})
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> reply(team, asker)
    |> subject(subject(team))
    |> text_body(Enum.map_join(paragraphs, "\n\n", &text/1) <> "\n")
    |> html_body(Enum.map_join(paragraphs, "\n", &html/1) <> "\n")
  end

  @doc ~s(Pure. "Coast Range SAR needs a photo for your ID card".)
  def subject(team), do: "#{team.name} needs a photo for your ID card"

  @doc """
  Pure. The email as plain paragraphs and `{:button, label, url}`, so its text and HTML
  can't drift apart.
  """
  def paragraphs(member, team, asker, message, url, clean_up?) do
    take_one =
      if clean_up?,
        do: "Take one with your phone: it takes a minute, and any background works.",
        else: "Take one with your phone: it takes a minute."

    Enum.reject(
      [
        "Hi #{member.name},",
        "#{team.name} needs a new photo for your ID card. #{take_one}",
        message && "#{(asker && asker.name) || "A team admin"}: “#{message}”",
        {:button, "Add a photo", url},
        "#{team.name}, through SAR Duty"
      ],
      &is_nil/1
    )
  end

  defp reply(email, _team, nil), do: email
  defp reply(email, team, asker), do: reply_to(email, {team.name, asker.email})

  defp text({:button, label, url}), do: "#{label}:\n#{url}"
  defp text(paragraph), do: paragraph

  defp html({:button, label, url}),
    do: ~s(<p><a href="#{escape(url)}" style="#{@button}">#{escape(label)}</a></p>)

  defp html(paragraph),
    do: "<p>#{paragraph |> escape() |> String.replace("\n", "<br>")}</p>"

  defp escape(string), do: string |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end

defmodule App.Mailer.IntegrationTestMailer do
  @moduledoc "The test email from Adminland › Integrations (#789). Sent inline: the admin waits for it."
  import Swoosh.Email

  @doc "Pure. The test email to `to`, sent by the site admin `sender_email` at `now`."
  def build(to, sender_email, now) do
    new()
    |> to(to)
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("Test email from SAR Duty")
    |> text_body("""
    This is a test from Adminland › Integrations, sent by #{sender_email} on #{Service.Format.month_day_time(now, "America/Vancouver")}.

    If you got it, email works.
    """)
  end
end

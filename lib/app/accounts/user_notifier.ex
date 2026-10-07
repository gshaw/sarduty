defmodule App.Accounts.UserNotifier do
  import Swoosh.Email

  alias App.Adapter.Twilio
  alias App.Mailer

  # The login email. The code is in the subject too, so a phone's notification shows it
  # without opening the email. The last line binds the code to this site's domain, in the
  # format of Apple's origin-bound code draft, so Safari can suggest it. The draft's
  # One-Time-Code header would do the same, but Cloudflare rejects headers off its list.
  def deliver_login_code(user, code) do
    host = Web.Endpoint.host()

    email =
      new()
      |> to(user.email)
      |> from({"SAR Duty", "noreply@sarduty.com"})
      |> subject("Your SAR Duty login code: #{code}")
      |> text_body("""
      Your code to log in to SAR Duty:

      #{code}

      Enter it on the login page. It works once, for 15 minutes. If you did not ask for it,
      ignore this email.

      @#{host} ##{code}
      """)
      |> html_body(login_html(code, host))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  # Sent when wrong login codes block an email or number for the day (#176). The owner
  # can still log in from a browser they've used before.
  def deliver_login_blocked(email_address) do
    new()
    |> to(email_address)
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("Wrong login codes entered for your SAR Duty account")
    |> text_body("""
    Someone entered 20 wrong login codes for your SAR Duty account today. New browsers
    cannot log in to it until tomorrow.

    A browser you've logged in with before still can. If this was not you, nothing else is
    needed: the codes were wrong, and they only work for 15 minutes.
    """)
    |> Mailer.deliver()
  end

  # The login text. The last line is the one-time code format iOS and Android read to
  # offer the code on the login page, bound to this site's domain.
  def deliver_login_text(phone, code) do
    Twilio.send_sms(phone, """
    Your SAR Duty login code: #{code}

    It works once, for 15 minutes.

    @#{Web.Endpoint.host()} ##{code}\
    """)
  end

  @doc "Tells the admins a team signed itself up. Sends nothing when there are none."
  def deliver_team_signed_up([], _team, _signer_email), do: {:ok, nil}

  def deliver_team_signed_up(admin_emails, team, signer_email) do
    new()
    |> to(admin_emails)
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("New team on SAR Duty: #{team.name}")
    |> text_body("""
    #{team.name} signed up to SAR Duty.

    Signed up by: #{signer_email}
    Team page: #{Web.Endpoint.url()}/teams/#{team.subdomain}
    D4H access key from: #{team.d4h_access_key_owner || "unknown"}

    Its first D4H refresh has started. Review it on #{Web.Endpoint.url()}/admin.
    """)
    |> Mailer.deliver()
  end

  # cspell:ignore Segoe -- Windows' system font, in the email's font stack
  # The logo is a PNG at 2x, since Gmail won't show SVG (see /styles/logo).
  # The domain line is hidden: it's for Mail, not people.
  defp login_html(code, host) do
    logo = Web.Endpoint.url() <> "/images/sarduty-logo-96.png"

    """
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 16px; color: #18181b; max-width: 480px;">
      <img src="#{logo}" width="48" height="48" alt="SAR Duty" style="display: block; border: 0;">
      <p>Your code to log in to SAR Duty:</p>
      <p style="margin: 24px 0; font-size: 32px; font-weight: 700; letter-spacing: 6px; font-family: ui-monospace, Menlo, monospace;">#{code}</p>
      <p style="color: #52525b; font-size: 14px;">Enter it on the login page. It works once, for 15 minutes. If you did not ask for it, ignore this email.</p>
      <p style="display: none; font-size: 0; line-height: 0; max-height: 0; overflow: hidden;">@#{host} ##{code}</p>
    </div>
    """
  end
end

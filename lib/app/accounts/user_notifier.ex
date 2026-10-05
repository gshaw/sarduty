defmodule App.Accounts.UserNotifier do
  import Swoosh.Email

  alias App.Mailer

  # The login email. The code is in the subject too, so a phone's notification shows it
  # without opening the email.
  def deliver_login_code(user, code) do
    email =
      new()
      |> to(user.email)
      |> from({"SAR Duty", "noreply@sarduty.com"})
      |> subject("Your SAR Duty login code: #{code}")
      |> text_body("""
      Your code to log in to SAR Duty:

      #{code}

      Enter it on the login page. It works once, for 15 minutes. If you didn't ask for it,
      ignore this email.
      """)
      |> html_body(login_html(code))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  # The login text. The last line is the one-time code format iOS and Android read to
  # offer the code on the login page, bound to this site's domain.
  def deliver_login_text(phone, code) do
    App.Adapter.Twilio.send_sms(phone, """
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
    Team page: #{Web.Endpoint.url()}/#{team.subdomain}
    D4H access key from: #{team.d4h_access_key_owner || "unknown"}

    Its first D4H refresh has started. Review it on #{Web.Endpoint.url()}/admin.
    """)
    |> Mailer.deliver()
  end

  # cspell:ignore Segoe -- Windows' system font, in the email's font stack
  defp login_html(code) do
    """
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 16px; color: #18181b; max-width: 480px;">
      <p>Your code to log in to SAR Duty:</p>
      <p style="margin: 24px 0; font-size: 32px; font-weight: 700; letter-spacing: 6px; font-family: ui-monospace, Menlo, monospace;">#{code}</p>
      <p style="color: #52525b; font-size: 14px;">Enter it on the login page. It works once, for 15 minutes. If you didn't ask for it, ignore this email.</p>
    </div>
    """
  end
end

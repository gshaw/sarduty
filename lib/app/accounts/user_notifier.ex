defmodule App.Accounts.UserNotifier do
  import Swoosh.Email

  alias App.Accounts.UserToken
  alias App.Adapter.D4H
  alias App.Adapter.Twilio
  alias App.Mailer

  # The login email. The code is in the subject too, so a phone's notification shows it
  # without opening the email. The last line binds the code to this site's domain, in the
  # format of Apple's origin-bound code draft, so Safari can suggest it. The draft's
  # One-Time-Code header would do the same, but Cloudflare rejects headers off its list.
  # People read the code in groups of 4; the bound line keeps it whole, since a space
  # there would end it.
  def deliver_login_code(user, code) do
    host = Web.Endpoint.host()
    shown = UserToken.format_code(code)

    email =
      new()
      |> to(user.email)
      |> from({"SAR Duty", "noreply@sarduty.com"})
      |> subject("Your SAR Duty login code: #{shown}")
      |> text_body("""
      Your code to log in to SAR Duty:

      #{shown}

      Enter it on the login page. It works once, for 15 minutes. If you did not ask for it,
      ignore this email.

      @#{host} ##{code}
      """)
      |> html_body(login_html(code, shown, host))
      |> Mailer.for_no_team()

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
    |> Mailer.for_no_team()
    |> Mailer.deliver()
  end

  # The last line of a code text is the one-time code format iOS and Android read to
  # offer the code on the page, bound to this site's domain.
  @doc "A code that proves a member gets texts at a new number (#156), from `team_id`."
  def deliver_confirm_text(phone, code, team_id) do
    Twilio.send_sms(
      phone,
      """
      Your SAR Duty confirmation code: #{UserToken.format_code(code)}

      It works once, for 15 minutes.

      @#{Web.Endpoint.host()} ##{code}\
      """,
      team_id
    )
  end

  @doc "Tells a member, at their email, that their mobile number changed (#156)."
  def deliver_phone_changed(email_address, team, new_phone) do
    team_name = team.name

    email =
      new()
      |> to(email_address)
      |> from({"SAR Duty", "noreply@sarduty.com"})
      |> subject("Your mobile number on #{team_name} changed")
      |> text_body("""
      Your mobile number on #{team_name} is now #{new_phone}. You changed it in SAR Duty, and your team's records have it too.

      If you did not make this change, tell one of your team admins.
      """)
      |> Mailer.for_team(team)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  # A login is no team's. Text login never reaches a demo team's member, whose number a
  # visitor typed: Member.current_emails_with_phone/2 leaves them out.
  def deliver_login_text(phone, code) do
    Twilio.send_sms(
      phone,
      """
      Your SAR Duty login code: #{UserToken.format_code(code)}

      It works once, for 15 minutes.

      @#{Web.Endpoint.host()} ##{code}\
      """,
      :no_team
    )
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
    Records in: #{D4H.service_name(team)}
    Access key from: #{team.d4h_access_key_owner || "unknown"}

    Its first refresh has started. Review it on #{Web.Endpoint.url()}/admin.
    """)
    |> Mailer.for_no_team()
    |> Mailer.deliver()
  end

  @doc "Tells the admins a team was deleted. Sends nothing when there are none."
  def deliver_team_deleted([], _args), do: {:ok, nil}

  def deliver_team_deleted(admin_emails, args) do
    undo =
      if args["snapshot"],
        do: "A copy of the team's data is on the server for 7 days:\n#{args["snapshot"]}",
        else: "No copy of the team's data was taken."

    new()
    |> to(admin_emails)
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("Team deleted from SAR Duty: #{args["name"]}")
    |> text_body("""
    #{args["name"]} (#{args["subdomain"]}) was deleted from SAR Duty, with all its data.

    Deleted by: #{args["deleted_by"]}
    #{service_line(args)}

    #{undo}
    """)
    |> Mailer.for_no_team()
    |> Mailer.deliver()
  end

  defp service_line(%{"records" => true}),
    do:
      "Its SAR Duty Records team is switched off, and goes in 7 days. Switch it on in Records' admin to keep it."

  defp service_line(args), do: "Nothing in #{args["service"]} changed."

  # cspell:ignore Segoe -- Windows' system font, in the email's font stack
  # The logo is a PNG at 2x, since Gmail won't show SVG (see /styles/logo).
  # The domain line is hidden: it's for Mail, not people.
  defp login_html(code, shown, host) do
    logo = Web.Endpoint.url() <> "/images/sarduty-logo-96.png"

    """
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 16px; color: #18181b; max-width: 480px;">
      <img src="#{logo}" width="48" height="48" alt="SAR Duty" style="display: block; border: 0;">
      <p>Your code to log in to SAR Duty:</p>
      <p style="margin: 24px 0; font-size: 32px; font-weight: 700; letter-spacing: 6px; font-family: ui-monospace, Menlo, monospace;">#{shown}</p>
      <p style="color: #52525b; font-size: 14px;">Enter it on the login page. It works once, for 15 minutes. If you did not ask for it, ignore this email.</p>
      <p style="display: none; font-size: 0; line-height: 0; max-height: 0; overflow: hidden;">@#{host} ##{code}</p>
    </div>
    """
  end
end

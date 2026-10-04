defmodule App.Accounts.UserNotifier do
  import Swoosh.Email

  alias App.Mailer

  # The login email: a button in mail apps that show HTML, the plain link otherwise.
  def deliver_login_link(user, url) do
    email =
      new()
      |> to(user.email)
      |> from({"SAR Duty", "noreply@sarduty.com"})
      |> subject("Log in to SAR Duty")
      |> text_body("""
      Use this link to log in to SAR Duty:

      #{url}

      It works once, for 15 minutes. If you didn't ask for it, ignore this email.
      """)
      |> html_body(login_html(url))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  # cspell:ignore Segoe -- Windows' system font, in the email's font stack
  defp login_html(url) do
    url = url |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    """
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 16px; color: #18181b; max-width: 480px;">
      <p>Tap the button to log in to SAR Duty.</p>
      <p style="margin: 24px 0;">
        <a href="#{url}" style="background: #16a34a; color: #ffffff; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 600; display: inline-block;">Log in</a>
      </p>
      <p style="color: #52525b; font-size: 14px;">It works once, for 15 minutes. If you didn't ask for it, ignore this email.</p>
      <p style="color: #71717a; font-size: 12px; word-break: break-all;">Or open #{url}</p>
    </div>
    """
  end
end

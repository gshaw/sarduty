defmodule App.Accounts.UserNotifier do
  import Swoosh.Email

  alias App.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"SAR Duty", "noreply@sarduty.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_login_link(user, url) do
    deliver(user.email, "Log in to SAR Duty", """
    Use this link to log in to SAR Duty:

    #{url}

    It works once, for 15 minutes. If you didn't ask for it, ignore this email.
    """)
  end
end

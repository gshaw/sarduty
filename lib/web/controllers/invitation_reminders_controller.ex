defmodule Web.InvitationRemindersController do
  use Web, :controller

  alias App.Model.Member
  alias App.Operation.SetInvitationReminders
  alias App.Repo
  alias Web.ReplyLinks

  # A mail app's one-click unsubscribe (RFC 8058, #444): it posts
  # `List-Unsubscribe=One-Click` to the reminder's List-Unsubscribe URL, with no session
  # and no CSRF token. The token alone turns the member's invitation reminders off.
  def unsubscribe(conn, %{"token" => token}) do
    with {:ok, member_id} <- ReplyLinks.verify_reminders(token),
         %Member{} = member <- Repo.get(Member, member_id) do
      SetInvitationReminders.call(member, false)
      send_resp(conn, 200, "Invitation reminders are off.")
    else
      _bad -> send_resp(conn, 404, "This link does not work.")
    end
  end
end

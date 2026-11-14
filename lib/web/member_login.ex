defmodule Web.MemberLogin do
  @moduledoc """
  The check before a member changes their own details on Your membership: Change mobile
  number, Change mailing address, Change emergency contacts, and Change fields (#156).
  """

  alias App.Model.Member

  @doc """
  Calls `fun` with the member, logged in again, in case the team turned member logins off
  since the page opened, and returns its socket. Without a login, back to the home page.
  A team admin viewing as the member never gets here: Web.UserAuth refuses.
  """
  def with_login(socket, fun) do
    %{current_user: user, current_member: member} = socket.assigns

    case Member.get_login(user.email, member.id, DateTime.utc_now()) do
      nil -> Phoenix.LiveView.redirect(socket, to: "/")
      member -> fun.(member)
    end
  end
end

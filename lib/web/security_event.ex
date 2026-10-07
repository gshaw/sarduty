defmodule Web.SecurityEvent do
  @moduledoc """
  Records a login, sign-up, or card check event (App.Model.Event) with the client's IP
  and user agent. A LiveView has no request, so it passes the `client_ip` and
  `user_agent` it kept from mount.
  """

  alias App.Model.Event
  alias Web.VerifyLimit

  def record(%Plug.Conn{} = conn, kind, attrs) do
    user_agent = conn |> Plug.Conn.get_req_header("user-agent") |> List.first()
    Event.record!(kind, [ip: VerifyLimit.client_ip(conn), user_agent: user_agent] ++ attrs)
  end

  def record(%{client_ip: ip, user_agent: user_agent}, kind, attrs),
    do: Event.record!(kind, [ip: ip, user_agent: user_agent] ++ attrs)

  defdelegate who(email_or_phone), to: Event
end

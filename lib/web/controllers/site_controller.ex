defmodule Web.SiteController do
  use Web, :controller

  # security.txt (RFC 9116, #824), the same file on both hosts. Built from the app's own
  # hosts, so dev serves its own. Expires is under a year out, as the RFC wants, and moves
  # with each request.
  def security_txt(conn, _params) do
    expires = Date.utc_today() |> Date.add(180) |> Date.to_iso8601()
    path = "/.well-known/security.txt"

    text = """
    Contact: mailto:support@sarduty.com
    Expires: #{expires}T00:00:00Z
    Preferred-Languages: en
    Canonical: #{Web.Endpoint.url()}#{path}
    Canonical: #{Web.VerifyHost.url()}#{path}
    Policy: https://github.com/gshaw/sarduty/security/policy
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, text)
  end

  @doc "RFC 9116's legacy path."
  def to_security_txt(conn, _params), do: redirect(conn, to: ~p"/.well-known/security.txt")
end

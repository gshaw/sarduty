defmodule Web.CertificateResponse do
  @moduledoc """
  Sends an award's certificate (#314), for a member's own route and a team admin's. The
  sandbox and nosniff headers keep a file from running as a page, even one opened inline.
  """

  import Plug.Conn

  alias App.Operation.LoadCertificate

  def send_certificate(conn, team, award) do
    case LoadCertificate.call(team, award) do
      {:ok, file} ->
        disposition = if file.inline?, do: "inline", else: "attachment"

        conn
        |> put_resp_content_type(file.content_type, nil)
        |> put_resp_header(
          "content-disposition",
          ~s(#{disposition}; filename="#{file.filename}")
        )
        |> put_resp_header("cache-control", "private, max-age=3600")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-security-policy", "sandbox")
        |> send_resp(200, file.body)

      :error ->
        send_resp(conn, :not_found, "")
    end
  end
end

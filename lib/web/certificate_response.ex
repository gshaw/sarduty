defmodule Web.CertificateResponse do
  @moduledoc """
  Sends a certificate: an award's, read from D4H (#314), or one a member sent that waits
  for a team admin (#493). The sandbox and nosniff headers keep a file from running as a
  page, even one opened inline. Chrome still shows a PDF under the sandbox header, in its
  own tab and in a frame, so long as the frame has no `sandbox` attribute.
  """

  import Plug.Conn

  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Operation.LoadCertificate

  def send_certificate(conn, team, award) do
    case LoadCertificate.call(team, award) do
      {:ok, file} -> send_file(conn, file)
      :error -> send_resp(conn, :not_found, "")
    end
  end

  @doc "A sent certificate's file, while SAR Duty keeps it; a 404 once it is gone."
  def send_sent(conn, %Certificate{} = certificate) do
    case CertificateFile.bytes(certificate) do
      nil ->
        send_resp(conn, :not_found, "")

      bytes ->
        send_file(conn, %{
          body: bytes,
          content_type: certificate.content_type,
          filename: certificate.file_name,
          # Only a PDF or a JPEG is kept (Service.CertificateFile).
          inline?: true
        })
    end
  end

  defp send_file(conn, file) do
    disposition = if file.inline?, do: "inline", else: "attachment"

    conn
    |> put_resp_content_type(file.content_type, nil)
    |> put_resp_header(
      "content-disposition",
      ~s(#{disposition}; filename="#{safe(file.filename)}")
    )
    |> put_resp_header("cache-control", "private, max-age=3600")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("content-security-policy", "sandbox")
    |> send_resp(200, file.body)
  end

  # A member's file name goes in a header, so quotes and line breaks go.
  defp safe(name), do: String.replace(name, ~r/["\\\r\n]/, "")
end

defmodule Web.VerifyHost do
  @moduledoc """
  The verify site's own host, `verify.` plus the app's: verify.sarduty.com in production.
  A card's QR code links here. It serves only the check, never the app or its login.
  """

  def host, do: "verify." <> Web.Endpoint.host()

  def url, do: Web.Endpoint.struct_url() |> Map.put(:host, host()) |> URI.to_string()

  @doc "Hosts whose card links the page's scanner accepts."
  def trusted_hosts, do: [host()]
end

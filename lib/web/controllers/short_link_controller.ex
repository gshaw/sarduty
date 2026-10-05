defmodule Web.ShortLinkController do
  use Web, :controller

  alias App.Model.ShortLink
  alias Web.ShortLinkLimit
  alias Web.VerifyLimit

  @doc "Sends /s/<code> on to its target. A missing or expired code is not found."
  def show(conn, %{"code" => code}) do
    ip = VerifyLimit.client_ip(conn)
    if ShortLinkLimit.limited?(ip), do: raise(Web.Status.TooManyRequests)

    code = String.downcase(code)

    link =
      if code =~ ShortLink.code_format(), do: ShortLink.find_by_code(code, DateTime.utc_now())

    if link do
      redirect(conn, to: link.target)
    else
      ShortLinkLimit.miss(ip)
      raise Web.Status.NotFound
    end
  end
end

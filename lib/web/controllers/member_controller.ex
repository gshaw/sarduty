defmodule Web.MemberController do
  use Web, :controller

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.LoadImage

  # The square photo on the member page, fetched with the signed-in user's D4H key.
  def image(conn, params) do
    member = Member.find!(conn.assigns.current_team, params["id"])
    d4h = D4H.build_context_from_user(conn.assigns.current_user)

    conn
    |> put_resp_content_type("image/png", nil)
    |> send_resp(200, LoadImage.photo(member, :square, d4h))
  end
end

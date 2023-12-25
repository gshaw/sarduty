defmodule Web.MemberController do
  use Web, :controller

  alias App.Adapter.D4H
  alias App.Model.Member

  def image(conn, params) do
    member = Member.get!(params["id"])
    d4h = D4H.build_context(conn.assigns.current_user)

    case D4H.fetch_member_image(d4h, member.d4h_member_id) do
      {:ok, image, filename} ->
        send_download(conn, {:binary, image}, filename: filename)

      {:error, _response} ->
        send_download(conn, {:file, "assets/img/member.png"})
    end
  end
end

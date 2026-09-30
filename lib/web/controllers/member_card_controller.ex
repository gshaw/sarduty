defmodule Web.MemberCardController do
  use Web, :controller

  alias App.Adapter.D4H
  alias App.Model.MemberCard

  # The photo on /verify. Public, so it answers only for a card that isn't cancelled.
  def photo(conn, %{"code" => input}) do
    with code when is_binary(code) <- MemberCard.normalize_code(input),
         %MemberCard{revoked_at: nil} = card <- MemberCard.find_by_code(code) do
      conn
      |> put_resp_header("cache-control", "private, max-age=300")
      |> send_photo(card)
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end

  defp send_photo(conn, %MemberCard{member: member}) do
    d4h = D4H.build_context_from_team(member.team)

    case D4H.fetch_member_image(d4h, member.d4h_member_id) do
      {:ok, image, filename} ->
        send_download(conn, {:binary, image}, filename: filename, disposition: :inline)

      {:error, _response} ->
        path = Application.app_dir(:sarduty, "/priv/static/images/member.png")
        send_download(conn, {:file, path}, disposition: :inline)
    end
  end
end

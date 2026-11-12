defmodule Web.MemberController do
  use Web, :controller

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Operation.LoadImage

  # The square photo in the member page's header, fetched with the team's D4H key, or a
  # 404 when D4H has none, so the header shows the member's initials.
  def image(conn, params) do
    team = conn.assigns.current_team
    member = %{Member.find!(team, params["id"]) | team: team}

    case LoadImage.page_photo(member) do
      nil ->
        send_resp(conn, :not_found, "")

      png ->
        conn
        |> put_resp_content_type("image/png", nil)
        |> put_resp_header("cache-control", "private, max-age=3600")
        |> send_resp(200, png)
    end
  end

  # The photo as the team's records keep it, full size and uncropped, as a download
  # named for the member (#1028). It passes through: SAR Duty keeps no copy. The bytes
  # come from outside, so nosniff and sandbox keep them from running as a page, as for a
  # certificate (Web.CertificateResponse).
  def original_image(conn, params) do
    team = conn.assigns.current_team
    member = Member.find!(team, params["id"])
    d4h = D4H.build_context_from_team(team)

    case D4H.fetch_member_original(d4h, member.d4h_member_id) do
      {:ok, bytes, content_type} ->
        extension = content_type |> MIME.extensions() |> List.first("jpg")
        filename = String.replace("#{member.name}.#{extension}", ~r/["\\\r\n]/, "")

        conn
        |> put_resp_content_type(content_type, nil)
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-security-policy", "sandbox")
        |> send_resp(200, bytes)

      {:error, _response} ->
        send_resp(conn, :not_found, "")
    end
  end

  # A member's certificate (#314), looked up through the team and then the member.
  def certificate(conn, %{"id" => id, "award_id" => award_id}) do
    team = conn.assigns.current_team
    award = team |> Member.find!(id) |> MemberQualificationAward.find_certificate!(award_id)
    Web.CertificateResponse.send_certificate(conn, team, award)
  end
end

defmodule Web.MemberController do
  use Web, :controller

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

  # A member's certificate (#314), looked up through the team and then the member.
  def certificate(conn, %{"id" => id, "award_id" => award_id}) do
    team = conn.assigns.current_team
    award = team |> Member.find!(id) |> MemberQualificationAward.find_certificate!(award_id)
    Web.CertificateResponse.send_certificate(conn, team, award)
  end
end

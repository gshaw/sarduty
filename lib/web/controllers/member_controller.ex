defmodule Web.MemberController do
  use Web, :controller

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Operation.LoadImage

  # The square photo on the member page, fetched with the team's D4H key.
  def image(conn, params) do
    member = Member.find!(conn.assigns.current_team, params["id"])
    d4h = D4H.build_context_from_team(conn.assigns.current_team)

    conn
    |> put_resp_content_type("image/png", nil)
    |> send_resp(200, LoadImage.photo(member, :square, d4h))
  end

  # A member's certificate (#314), looked up through the team and then the member.
  def certificate(conn, %{"id" => id, "award_id" => award_id}) do
    team = conn.assigns.current_team
    award = team |> Member.find!(id) |> MemberQualificationAward.find_certificate!(award_id)
    Web.CertificateResponse.send_certificate(conn, team, award)
  end
end

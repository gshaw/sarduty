defmodule Web.MemberCardController do
  use Web, :controller

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.LoadImage
  alias App.Repo
  alias Web.VerifyLimit

  # The photo on /verify, also the Apple thumbnail. Public, so it answers only for a card
  # that isn't cancelled, and its 404s count toward the verify site's limit.
  def photo(conn, %{"code" => input}) do
    ip = VerifyLimit.client_ip(conn)

    if VerifyLimit.limited?(ip) do
      send_resp(conn, :too_many_requests, "")
    else
      conn = send_photo(conn, input, :square)
      if conn.status == 404, do: VerifyLimit.miss(ip)
      conn
    end
  end

  # The photo centered in the Google pass's hero banner.
  def banner(conn, %{"code" => input}), do: send_photo(conn, input, :banner)

  defp send_photo(conn, input, shape) do
    with code when is_binary(code) <- MemberCard.normalize_code(input),
         %MemberCard{revoked_at: nil} = card <- MemberCard.find_by_code(code) do
      conn
      |> put_resp_header("cache-control", "private, max-age=300")
      |> put_resp_content_type("image/png", nil)
      |> send_resp(200, LoadImage.photo(card.member, shape))
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end

  # The Apple Wallet pass for the member's current card, for a team manager to open on
  # an iPhone or send to the member.
  def pass(conn, %{"id" => id}) do
    team = conn.assigns.current_team
    member = Member.find!(team, id)

    with %MemberCard{} = card <- MemberCard.find_current(team, member),
         card = Repo.preload(card, member: :team),
         {:ok, pkpass} <- BuildApplePass.call(card, DateTime.utc_now()) do
      send_download(conn, {:binary, pkpass},
        filename: "#{team.subdomain}-member-card.pkpass",
        content_type: "application/vnd.apple.pkpass"
      )
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end

  # Sends the current card's pass to Google, then opens Google's "Add to Google Wallet"
  # page for it.
  def google_pass(conn, %{"id" => id}) do
    team = conn.assigns.current_team
    member = Member.find!(team, id)

    with %MemberCard{} = card <- MemberCard.find_current(team, member),
         card = Repo.preload(card, member: :team),
         {:ok, url} <- BuildGooglePass.call(card, DateTime.utc_now()) do
      redirect(conn, external: url)
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end
end

defmodule Web.MemberCardController do
  use Web, :controller

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.LoadImage
  alias App.Repo
  alias Web.VerifyLimit

  # The photo on the verify site. Public, so it answers only for an active member's card:
  # not for a cancelled card, nor for someone who has left the team (#176). Its 404s count
  # toward the verify site's limit.
  def photo(conn, %{"code" => input}), do: send_limited_photo(conn, input, :square)

  # The photo centered in the Google pass's hero banner. Counts misses like the photo, so
  # it can't be used to test codes without limit (#176).
  def banner(conn, %{"code" => input}), do: send_limited_photo(conn, input, :banner)

  defp send_limited_photo(conn, input, shape) do
    ip = VerifyLimit.client_ip(conn)

    if VerifyLimit.limited?(ip) do
      send_resp(conn, :too_many_requests, "")
    else
      conn = send_photo(conn, input, shape)
      if conn.status == 404, do: VerifyLimit.miss(ip)
      conn
    end
  end

  defp send_photo(conn, input, shape) do
    with code when is_binary(code) <- MemberCard.normalize_code(input),
         %MemberCard{} = card <- MemberCard.find_by_code(code),
         :active <- MemberCard.status(card, DateTime.utc_now()) do
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
         card = Repo.preload(card, member: [team: :organization]),
         {:ok, pkpass} <- BuildApplePass.call(card, DateTime.utc_now()) do
      send_download(conn, {:binary, pkpass},
        filename: "#{team.subdomain}-id-card.pkpass",
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
         card = Repo.preload(card, member: [team: :organization]),
         {:ok, url} <- BuildGooglePass.call(card, DateTime.utc_now()) do
      redirect(conn, external: url)
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end
end

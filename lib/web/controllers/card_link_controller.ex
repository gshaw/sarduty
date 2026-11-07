defmodule Web.CardLinkController do
  use Web, :controller

  alias App.Model.MemberCard
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias Web.CardLinks

  # The badges on an ID card's page (#952): no login, only the link's token. Each builds
  # the card's pass when the member taps it, as Your membership's buttons do
  # (MeController), and only for a live card in good standing. Anything else is a 404,
  # the page having already said why.

  def apple_pass(conn, %{"token" => token}) do
    now = DateTime.utc_now()

    with %MemberCard{} = card <- active_card(token, now),
         {:ok, pkpass} <- BuildApplePass.call(card, now) do
      send_download(conn, {:binary, pkpass},
        filename: "#{card.member.team.subdomain}-id-card.pkpass",
        content_type: "application/vnd.apple.pkpass"
      )
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end

  def google_pass(conn, %{"token" => token}) do
    now = DateTime.utc_now()

    with %MemberCard{} = card <- active_card(token, now),
         {:ok, url} <- BuildGooglePass.call(card, now) do
      redirect(conn, external: url)
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end

  defp active_card(token, now) do
    with %MemberCard{} = card <- CardLinks.find_card(token),
         :active <- MemberCard.link_status(card, now) do
      card
    else
      _ -> nil
    end
  end
end

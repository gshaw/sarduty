defmodule Web.CardLinkController do
  use Web, :controller

  alias App.Model.MemberCard
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.DrawMemberCard
  alias Web.CardLinks

  # The badges on an ID card's page (#952): no login, only the link's token. Each builds
  # the card's pass when the member taps it, as Your membership's buttons do
  # (MeController), and only for a live card in good standing. Anything else is a 404,
  # the page having already said why. The card's two sides and its PDF (#973) are
  # drawn on each request, as a pass is built, so they always show today's card.

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

  def image(conn, %{"token" => token}), do: send_drawing(conn, token, :image)
  def pdf(conn, %{"token" => token}), do: send_drawing(conn, token, :print)

  # Inline, so the page shows the pictures and a phone opens the PDF to print; the card
  # page's Save image names the file. A drawing that fails raises: it's a bug, not a
  # card that can't be shown.
  defp send_drawing(conn, token, side) do
    now = DateTime.utc_now()

    case active_card(token, now) do
      nil ->
        send_resp(conn, :not_found, "")

      card ->
        {:ok, bytes} = DrawMemberCard.call(card, side)

        conn
        |> put_resp_header("cache-control", "private, max-age=300")
        |> send_download({:binary, bytes},
          filename: filename(card, side),
          content_type: if(side == :print, do: "application/pdf", else: "image/png"),
          disposition: :inline
        )
    end
  end

  defp filename(card, :print), do: "#{card.member.team.subdomain}-id-card.pdf"
  defp filename(card, :image), do: "#{card.member.team.subdomain}-id-card.png"

  defp active_card(token, now) do
    with %MemberCard{} = card <- CardLinks.find_card(token),
         :active <- MemberCard.link_status(card, now) do
      card
    else
      _ -> nil
    end
  end
end

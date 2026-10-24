defmodule Web.MeController do
  use Web, :controller

  alias App.Model.Certificate
  alias App.Model.MemberCard
  alias App.Model.MemberQualificationAward
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.BuildTaxCreditLetterAttachment
  alias App.Operation.LoadImage
  alias App.Repo

  # A member's own downloads (#156). Web.UserAuth.require_team_member sets `member` from
  # the login, so nothing here takes a member id from the URL. A team admin viewing as the
  # member (#425) gets the photo and the letter, but no Wallet pass: a pass would be the
  # member's, on the team admin's phone.

  plug :refuse_viewing_as when action in [:apple_pass, :google_pass]

  def apple_pass(conn, _params) do
    with %MemberCard{} = card <- current_card(conn),
         {:ok, pkpass} <- BuildApplePass.call(card, DateTime.utc_now()) do
      send_download(conn, {:binary, pkpass},
        filename: "#{card.member.team.subdomain}-id-card.pkpass",
        content_type: "application/vnd.apple.pkpass"
      )
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end

  def google_pass(conn, _params) do
    with %MemberCard{} = card <- current_card(conn),
         {:ok, url} <- BuildGooglePass.call(card, DateTime.utc_now()) do
      redirect(conn, external: url)
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end

  # The member's own photo, for Your membership. A 404 when D4H has none, so the page
  # shows their initials.
  def image(conn, _params) do
    case LoadImage.page_photo(conn.assigns.member) do
      nil ->
        send_resp(conn, :not_found, "")

      png ->
        conn
        |> put_resp_content_type("image/png", nil)
        |> put_resp_header("cache-control", "private, max-age=3600")
        |> send_resp(200, png)
    end
  end

  # An award's certificate (#314), looked up through the member.
  def certificate(conn, %{"id" => id}) do
    member = conn.assigns.member
    award = MemberQualificationAward.find_certificate!(member, id)
    Web.CertificateResponse.send_certificate(conn, member.team, award)
  end

  # A certificate the member sent (#493), while SAR Duty keeps its file.
  def sent_certificate(conn, %{"id" => id}) do
    certificate = Certificate.find_for_member!(conn.assigns.member, id)
    Web.CertificateResponse.send_sent(conn, certificate)
  end

  def tax_credit_letter(conn, %{"id" => id}) do
    letter = TaxCreditLetter.find_for_member!(conn.assigns.member, id)
    attachment = BuildTaxCreditLetterAttachment.call(letter)
    # Takes the letter off the member's "For you to do" (#389).
    if !conn.assigns.viewing_as, do: TaxCreditLetter.mark_downloaded(letter, DateTime.utc_now())

    conn
    |> put_resp_content_type(attachment.content_type)
    |> send_resp(200, attachment.content)
  end

  defp refuse_viewing_as(%{assigns: %{viewing_as: nil}} = conn, _opts), do: conn

  defp refuse_viewing_as(conn, _opts) do
    %{member: member} = conn.assigns

    conn
    |> put_flash(:error, Web.UserAuth.view_as_refusal(member))
    |> redirect(to: ~p"/teams/#{member.team}/me")
    |> halt()
  end

  defp current_card(conn) do
    member = conn.assigns.member

    case MemberCard.find_current(member.team, member) do
      nil -> nil
      card -> Repo.preload(card, member: [team: :organization])
    end
  end
end

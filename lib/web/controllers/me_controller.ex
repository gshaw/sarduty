defmodule Web.MeController do
  use Web, :controller

  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.BuildTaxCreditLetterAttachment
  alias App.Repo

  # A member's own downloads (#156). Web.UserAuth.require_team_member sets `member` from
  # the login, so nothing here takes a member id from the URL.

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

  def tax_credit_letter(conn, %{"id" => id}) do
    letter = TaxCreditLetter.find_for_member!(conn.assigns.member, id)
    attachment = BuildTaxCreditLetterAttachment.call(letter)

    conn
    |> put_resp_content_type(attachment.content_type)
    |> send_resp(200, attachment.content)
  end

  defp current_card(conn) do
    member = conn.assigns.member

    case MemberCard.find_current(member.team, member) do
      nil -> nil
      card -> Repo.preload(card, member: [team: :organization])
    end
  end
end

defmodule Web.MeController do
  use Web, :controller

  alias App.Adapter.D4H
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildGooglePass
  alias App.Operation.BuildTaxCreditLetterAttachment
  alias App.Repo
  alias App.ViewData.MemberRecords

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

  # A calendar file for an activity the member signed up for, found among their own
  # sign-ups, so no other activity is reachable by id.
  def calendar(conn, %{"id" => id}) do
    member = conn.assigns.member
    now = DateTime.utc_now()

    signed_up = MemberRecords.signed_up(member, now)

    case Enum.find(signed_up, &(Integer.to_string(&1.activity.id) == id)) do
      nil ->
        send_resp(conn, :not_found, "")

      %{activity: activity} ->
        ics =
          Service.Calendar.event(
            %{
              uid: "activity-#{activity.id}@sarduty.com",
              title: activity.title,
              starts_at: activity.started_at,
              ends_at: activity.finished_at,
              location: activity.address,
              url: if(!D4H.records?(member.team), do: D4H.activity_url(member.team, activity))
            },
            now
          )

        send_download(conn, {:binary, ics},
          filename: "#{member.team.subdomain}-activity-#{activity.id}.ics",
          content_type: "text/calendar"
        )
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

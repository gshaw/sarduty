defmodule Web.CertificateController do
  use Web, :controller

  alias App.Model.Certificate
  alias App.Model.Team

  # A sent certificate's file (#493), while SAR Duty keeps it: one URL for everyone
  # (#645). A team admin gets any of the team's; anyone else only their own, so a team
  # admin viewing as a member gets the member's.
  def file(conn, %{"id" => id}) do
    %{current_team: team, current_member: member, team_admin?: team_admin?} = conn.assigns
    if !Team.certificates?(team), do: raise(Web.Status.NotFound)

    certificate =
      if team_admin?,
        do: Certificate.find!(team, id),
        else: Certificate.find_for_member!(member, id)

    Web.CertificateResponse.send_sent(conn, certificate)
  end
end
